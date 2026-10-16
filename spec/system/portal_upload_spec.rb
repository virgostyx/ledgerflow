require 'rails_helper'

# B02b, in a real browser: a file is sent in chunks, a network that fails and repeats costs nothing, and the send counts as done only when the server has given its receipt.
RSpec.describe 'Sending a document from the portal', type: :system, js: true do
  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }
  let(:data)   { Random.new(3).bytes(2_500_000) }

  around do |example|
    previous = [ Rails.configuration.x.portal_host, Capybara.app_host, Capybara.always_include_port ]
    Rails.configuration.x.portal_host = 'portal.localhost'
    Capybara.app_host = 'http://portal.localhost'
    Capybara.always_include_port = true
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  ensure
    Rails.configuration.x.portal_host, Capybara.app_host, Capybara.always_include_port = previous
  end

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: 'collaborator', capabilities: %w[documents.upload])
    visit '/sign_in'
    fill_in 'Email', with: person.email
    fill_in 'Password', with: 'correct horse battery'
    click_button 'Continue'
    fill_in 'Code', with: Totp.code(person.totp_secret)
    click_button 'Sign in'
    expect(page).to have_content('Signed in as') # the sign-in is over before anything else is asked of the browser
  end

  def file_to_send(name = 'invoice.pdf', bytes = data)
    File.join(@dir, name).tap { |path| File.binwrite(path, bytes) }
  end

  def wait_for(message = 'condition')
    Timeout.timeout(20) { sleep 0.1 until yield }
  rescue Timeout::Error
    raise "timed out waiting for #{message}"
  end

  it 'sends a file in chunks and gets the receipt' do
    visit '/uploads/new'
    attach_file 'pick', file_to_send, make_visible: true

    wait_for('the receipt') { Portal::Upload.received.exists? }

    upload = Portal::Upload.sole
    expect(Digest::SHA256.hexdigest(upload.bytes)).to eq(Digest::SHA256.hexdigest(data))
    expect(upload.chunks.count).to eq(3)
    expect(page).not_to have_css('#outbox li')
    visit '/uploads'
    expect(page).to have_content('invoice.pdf')
  end

  it 'goes on after a network that fails, repeats and loses answers, with the same file at the end (criteria 1 and 2)' do
    visit '/uploads/new'
    page.execute_script(<<~JS)
      window.__chaos = { failed: 0, repeated: 0 };
      const real = window.fetch.bind(window);
      let puts = 0;
      window.fetch = async (url, opts = {}) => {
        if (opts.method === 'PUT') {
          puts += 1;
          if (puts === 2) { window.__chaos.failed += 1; throw new TypeError('network down'); }   // the second chunk never arrives
          if (puts === 3) { window.__chaos.repeated += 1; await real(url, opts); }                // the third is sent twice
        }
        if (opts.method === 'POST' && String(url).endsWith('/complete') && !window.__chaos.lostAnswer) { window.__chaos.lostAnswer = true; await real(url, opts); throw new TypeError('answer lost'); }
        return real(url, opts);
      };
    JS
    attach_file 'pick', file_to_send, make_visible: true

    wait_for('the end of the send') { Portal::Upload.received.exists? && page.evaluate_script("document.querySelectorAll('#outbox li').length") == 0 }

    expect(page.evaluate_script('window.__chaos')).to include('failed' => 1, 'repeated' => 1, 'lostAnswer' => true)
    expect(Portal::Upload.count).to eq(1)
    expect(Digest::SHA256.hexdigest(Portal::Upload.sole.bytes)).to eq(Digest::SHA256.hexdigest(data))
  end

  it 'keeps what could not be sent, says so, and sends it by itself when the page is opened again (criterion 3)' do
    visit '/uploads/new'
    page.execute_script("window.fetch = async () => { throw new TypeError('offline') }")
    attach_file 'pick', file_to_send('offline.pdf', 'x' * 1000), make_visible: true

    expect(page).to have_content('1 waiting to be sent')
    expect(Portal::Upload.count).to eq(0)

    visit '/uploads/new' # the network is back, the browser still holds the document
    wait_for('the receipt') { Portal::Upload.received.exists? }

    expect(Portal::Upload.sole.filename).to eq('offline.pdf')
    expect(page).not_to have_content('waiting to be sent')
  end

  it 'asks to sign in again when the session is over, and keeps the document' do
    visit '/uploads/new'
    Portal::Session.update_all(revoked_at: Time.current)
    attach_file 'pick', file_to_send('late.pdf', 'x' * 1000), make_visible: true

    expect(page).to have_link('Sign in again')
    expect(page).to have_content('1 waiting to be sent')
    expect(Portal::Upload.count).to eq(0)
  end
end

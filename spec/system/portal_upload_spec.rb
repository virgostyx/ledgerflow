require 'rails_helper'

# B02b, in a real browser: a file is sent in chunks, a network that fails and repeats costs nothing, and the send counts as done only when the server has given its receipt.
RSpec.describe 'Sending a document from the portal', type: :system, js: true, portal_browser: true do
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

  describe 'installed on a phone, without a network (criterion 3)' do
    def network(offline)
      page.driver.browser.network_conditions = { offline: offline, latency: 0, download_throughput: -1, upload_throughput: -1 }
    end

    it 'opens offline from the copy kept, keeps a document, and sends it by itself when the network is back' do
      visit '/uploads/new'
      wait_for('the worker and the copy of the page') do
        page.evaluate_script("(async () => { const keys = await caches.keys(); if (!keys.length) return false; return (await (await caches.open(keys[0])).keys()).length >= 3 })()") rescue false
      end

      network(true)
      begin
        visit '/uploads/new'
        expect(page).to have_content('Send documents')
        attach_file 'pick', file_to_send('train.pdf', 'x' * 1000), make_visible: true
        expect(page).to have_content('1 waiting to be sent')
        expect(Portal::Upload.count).to eq(0)
      ensure
        network(false)
      end

      wait_for('the receipt after the network came back') { Portal::Upload.received.exists? }
      expect(Portal::Upload.sole.filename).to eq('train.pdf')
    end

    it 'serves the manifest and the worker from the root, with the scope of the whole portal' do
      visit '/manifest.webmanifest'
      expect(page.text).to include('"start_url":"/"', '"display":"standalone"')
      visit '/service-worker.js'
      expect(page.text).to include('PortalOutbox', 'addEventListener("sync"')
    end
  end

  describe 'waiting sends expire after 30 days' do
    def waiting_since(days, name)
      page.driver.browser.execute_async_script(<<~JS, name, days)
        const [name, days, done] = arguments;
        PortalOutbox.save({ company: 0, kind: 'file', parts: [ { name, blob: new Blob(['x']) } ], batch: 'b', hint_kind: 'other', hint_note: '', state: 'waiting', created_at: Date.now() - days * 86400000 }).then(() => done(true));
      JS
    end

    it 'deletes what waited more than 30 days and warns about what is close' do
      visit '/uploads/new'
      page.execute_script("window.fetch = async () => { throw new TypeError('offline') }") # nothing leaves while this is tested
      waiting_since(31, 'too-old.pdf')
      waiting_since(26, 'nearly.pdf')

      visit '/uploads/new'
      page.execute_script("window.fetch = async () => { throw new TypeError('offline') }")
      page.execute_script('portalUpload.render()')

      expect(page).to have_content('nearly.pdf')
      expect(page).not_to have_content('too-old.pdf')
      expect(page).to have_content('1 will be deleted in less than 5 days')
    end
  end

  describe 'photos' do
    def photo(name, *convert_args, size: '1600x1200')
      path = File.join(@dir, name)
      system('convert', '-size', size, *convert_args, path) or raise 'convert failed'
      path
    end

    # something with edges: a grid of black and white squares
    def sharp = photo('sharp.jpg', 'pattern:checkerboard', '-scale', '400%')
    def blurred = photo('blurred.jpg', 'pattern:checkerboard', '-scale', '400%', '-blur', '0x30')
    def dark = photo('dark.jpg', 'xc:black')

    it 'warns about a blurry photo without blocking, and lets the person keep it' do
      visit '/uploads/new'
      attach_file 'camera', blurred, make_visible: true

      expect(page).to have_content('The photo is blurry')
      click_button 'Keep it'
      expect(page).not_to have_content('The photo is blurry')
      expect(page).to have_button('Send 1 page')
    end

    it 'warns about a dark photo' do
      visit '/uploads/new'
      attach_file 'camera', dark, make_visible: true
      expect(page).to have_content('The photo is too dark')
    end

    it 'says nothing of a sharp photo' do
      visit '/uploads/new'
      attach_file 'camera', sharp, make_visible: true
      expect(page).to have_button('Send 1 page')
      expect(page).not_to have_css('[role=alert]')
    end

    # the connection the browser reports (what the emulated network of an earlier example may have left is not the question here)
    def connection(effective_type: '4g', save_data: false)
      page.execute_script("Object.defineProperty(navigator, 'connection', { configurable: true, value: { effectiveType: '#{effective_type}', saveData: #{save_data} } })")
    end

    it 'sends a smaller picture when the connection is slow or the person saves data' do
      visit '/uploads/new'
      connection(save_data: true)
      attach_file 'camera', photo('big.jpg', 'xc:red', size: '3000x1500'), make_visible: true
      click_button 'Send 1 page'

      wait_for('the page') { Portal::Upload.received.exists? }

      expect(Open3.capture2('identify', '-format', '%wx%h', '-', stdin_data: Portal::Upload.sole.bytes, binmode: true).first).to eq('1280x640')
    end

    it 'reduces a large photo to 2000 pixels and sends the pages in the order chosen, as one batch' do
      visit '/uploads/new'
      connection
      attach_file 'camera', photo('first.jpg', 'xc:red', size: '3000x1500'), make_visible: true
      attach_file 'camera', photo('second.jpg', 'xc:blue', size: '800x600'), make_visible: true
      expect(page).to have_button('Send 2 pages')
      click_button 'Move down' # the first page goes after the second
      click_button 'Send 2 pages'

      wait_for('both pages') { Portal::Upload.received.count == 2 }

      pages = Portal::Upload.order(:page_number)
      expect(pages.map(&:page_number)).to eq([ 1, 2 ])
      expect(pages.map(&:page_count).uniq).to eq([ 2 ])
      expect(pages.map(&:batch_token).uniq.size).to eq(1)
      expect(pages.first.bytes.byteslice(0, 3)).to eq("\xFF\xD8\xFF".b)
      dims = pages.map { |u| Open3.capture2('identify', '-format', '%wx%h', '-', stdin_data: u.bytes, binmode: true).first }
      expect(dims).to eq([ '800x600', '2000x1000' ]) # second photo first, as moved; the large one reduced

      PortalAdmin::ReceiveUploads.call # the firm's side takes the pages out of quarantine: one PDF of two pages
      document = ActsAsTenant.with_tenant(entity) { Accounting::Document.sole }
      expect(PDF::Reader.new(StringIO.new(document.file.download)).page_count).to eq(2)
    end

    it 'turns a page a quarter' do
      visit '/uploads/new'
      attach_file 'camera', photo('wide.jpg', 'xc:green', size: '800x600'), make_visible: true
      click_button 'Rotate'
      click_button 'Send 1 page'

      wait_for('the page') { Portal::Upload.received.exists? }

      expect(Open3.capture2('identify', '-format', '%wx%h', '-', stdin_data: Portal::Upload.sole.bytes, binmode: true).first).to eq('600x800')
    end

    it 'removes a page' do
      visit '/uploads/new'
      attach_file 'camera', sharp, make_visible: true
      click_button 'Remove'
      expect(page).not_to have_button('Send 1 page')
    end
  end
end

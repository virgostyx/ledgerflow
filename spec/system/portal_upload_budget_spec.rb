require 'rails_helper'

# B02b, criterion 10: the page for sending documents stays light (JavaScript under 200 KB), is usable on a slow phone and a slow network, and keeps to the basics of accessibility.
RSpec.describe 'The page for sending documents on a small phone', type: :system, js: true, portal_browser: true do
  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }

  # The sizes of the buttons depend on the stylesheet, which is built from the views (and is not in the repository): a stale build would measure the wrong page.
  before(:all) { system('bin/rails', 'tailwindcss:build', out: File::NULL, err: File::NULL) }

  around do |example|
    previous = [ Rails.configuration.x.portal_host, Capybara.app_host, Capybara.always_include_port ]
    Rails.configuration.x.portal_host = 'portal.localhost'
    Capybara.app_host = 'http://portal.localhost'
    Capybara.always_include_port = true
    example.run
  ensure
    Rails.configuration.x.portal_host, Capybara.app_host, Capybara.always_include_port = previous
  end

  before do
    page.driver.browser.manage.window.resize_to(360, 640)
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: 'collaborator', capabilities: %w[documents.upload bank_lines.view])
    visit '/sign_in'
    fill_in 'Email', with: person.email
    fill_in 'Password', with: 'correct horse battery'
    click_button 'Continue'
    fill_in 'Code', with: Totp.code(person.totp_secret)
    click_button 'Sign in'
    expect(page).to have_content('Signed in as')
  end

  after { page.driver.browser.execute_cdp('Emulation.setCPUThrottlingRate', rate: 1) }

  def script_bytes
    page.evaluate_script("performance.getEntriesByType('resource').filter((r) => r.initiatorType === 'script' || r.name.endsWith('.js')).reduce((sum, r) => sum + (r.decodedBodySize || 0), 0)")
  end

  it 'loads less than 200 KB of JavaScript' do
    visit '/uploads/new'
    expect(script_bytes).to be_positive
    expect(script_bytes).to be < 200_000
  end

  it 'is ready within a few seconds on a slow network and a slow processor' do
    page.driver.browser.network_conditions = { offline: false, latency: 400, download_throughput: 50 * 1024, upload_throughput: 50 * 1024 } # about "slow 3G"
    page.driver.browser.execute_cdp('Emulation.setCPUThrottlingRate', rate: 4)

    page.execute_script("navigator.serviceWorker.getRegistrations().then((all) => all.forEach((r) => r.unregister()))") # a copy kept by the worker would hide the network
    visit '/uploads/new'
    expect(page).to have_content('Choose a file')
    ready = page.evaluate_script('performance.timing.domContentLoadedEventEnd - performance.timing.navigationStart')
    puts "slow profile: DOMContentLoaded after #{ready} ms"

    expect(ready).to be < 6000
  end

  it 'does not scroll sideways on a phone, on any page of the portal' do
    %w[/ /uploads/new /uploads /document_requests /mail /devices /preferences].each do |path|
      visit path
      expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true), "#{path} scrolls sideways at 360 px"
    end
  end

  it 'gives every field a label, the page a language and a title, and every button a name' do
    visit '/uploads/new'

    unlabelled = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('input:not([type=hidden]), select, textarea')).filter((e) => !(e.labels && e.labels.length) && !e.getAttribute('aria-label')).map((e) => e.id || e.name)
    JS
    expect(unlabelled).to eq([])
    expect(page.evaluate_script('document.documentElement.lang')).to eq('en')
    expect(page.evaluate_script('document.title')).not_to be_empty
    expect(page.evaluate_script("Array.from(document.querySelectorAll('button, a')).filter((e) => e.getClientRects().length && !(e.textContent || '').trim() && !e.getAttribute('aria-label')).length")).to eq(0)
  end

  it 'has big buttons for the actions of a phone' do
    visit '/'
    heights = page.evaluate_script("Array.from(document.querySelectorAll('main a.rounded')).map((a) => a.getBoundingClientRect().height)")
    expect(heights).not_to be_empty
    expect(heights.min).to be >= 44
  end

  it 'announces what happens to a screen reader' do
    visit '/uploads/new'
    expect(page).to have_css('#pending[role=status][aria-live=polite]', visible: :all)
  end
end

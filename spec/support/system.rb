require 'capybara/rspec'

Capybara.register_driver :selenium_chrome_headless do |app|
  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: Selenium::WebDriver::Chrome::Options.new(
      args: %w[headless no-sandbox disable-gpu disable-dev-shm-usage window-size=1400,900]
    )
  )
end

Capybara.default_driver    = :rack_test
Capybara.javascript_driver = :selenium_chrome_headless
Capybara.default_max_wait_time = 5
Capybara.enable_aria_label = true

RSpec.configure do |config|
  config.include Warden::Test::Helpers, type: :system

  config.before(:each, type: :system) do
    Warden.test_mode!
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :selenium_chrome_headless
  end

  config.after(:each, type: :system) do
    Warden.test_reset!
  end
end

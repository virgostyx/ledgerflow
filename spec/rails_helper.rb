require 'simplecov'
SimpleCov.start 'rails' do
  add_filter '/spec/'
  minimum_coverage 95
end

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
require 'view_component/test_helpers'
require 'view_component/system_test_helpers'
require 'webmock/rspec'

Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join('spec/fixtures') ]
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before(:suite) { Faker::Config.locale = :en }

  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActionMailbox::TestHelper,     type: :mailbox
  config.include ViewComponent::TestHelpers,    type: :component
  config.include Capybara::RSpecMatchers,       type: :component
  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::ControllerHelpers,  type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :system

  # VAT law reference data (Accounting::VatGrid reads it): seeded once, kept by every strategy below.
  VAT_REFERENCE_TABLES = %w[accounting_vat_codes accounting_vat_grid_mappings accounting_vat_account_grid_rules currencies].freeze

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
    Seeders::VatCodesSeeder.call
    Seeders::CurrenciesSeeder.call # currencies and their decimals (F11): reference data too
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation, { except: VAT_REFERENCE_TABLES }
  end

  # Concurrency specs use real threads and connections: nothing can stay inside an uncommitted transaction.
  config.before(:each, :concurrency) do
    DatabaseCleaner.strategy = :truncation, { except: VAT_REFERENCE_TABLES }
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

source "https://rubygems.org"

ruby "3.3.5"

gem "rails", "~> 8.1.3"
gem "propshaft"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false
gem "image_processing", "~> 2.0"

# UI Framework
gem "view_component"

# Auth & Autorisations
gem "devise"
gem "pundit"
gem "jwt"
gem "bcrypt", "~> 3.1.7"

# Logique métier
gem "light-service"
gem "aasm"

# Audit & Traçabilité
gem "paper_trail"

# PDF
gem "ferrum"
gem "prawn"
gem "prawn-table"

# XML / Peppol UBL
gem "nokogiri"

# Export
gem "caxlsx"
gem "caxlsx_rails"

# Import bancaire
gem "sepa_king"

# HTTP Client
gem "faraday"
gem "faraday-retry"
gem "httparty"

# Notifications
gem "noticed"

# Sécurité
gem "rack-attack"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false

  # RSpec
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "database_cleaner-active_record"
  gem "shoulda-matchers"
  gem "simplecov", require: false
end

group :development do
  gem "web-console"
  gem "bullet"
  gem "rack-mini-profiler"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "webmock"
  gem "vcr"
end

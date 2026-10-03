require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Ledgerflow
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # The Peppol simulator fakes deliveries: only development and test switch it on (validated by Entity).
    config.x.peppol_simulator_allowed = false
    # F01: whoever can validate, unlock or administer must sign in with a second factor (TOTP or a passkey).
    # The test suite switches it off (its request specs sign in with a helper); the specs of the flow switch it on.
    config.x.second_factor_required = true
    # F03: how far an uploaded archive is unpacked: files, total size once unpacked, compression ratio of one file.
    config.x.document_archive_limits = { files: 50, bytes: 100.megabytes, ratio: 100 }
    # F03: the domain of the addresses that receive documents by e-mail (documents+<secret>@<domain>); mail to it must reach
    # Action Mailbox (config.action_mailbox.ingress, see docs/dev/features/F03.md).
    # The historic shared-secret JWT of BudgetFlow: closed unless the operator asks for it (see docs/dev/api/inbound-api.md).
    config.x.legacy_jwt_enabled = ENV["LEGACY_JWT_ENABLED"] == "1"
    config.x.documents_mail_domain = ENV.fetch("DOCUMENTS_MAIL_DOMAIN", "documents.ledgerflow.example")
    # F03: an antivirus for uploaded documents, off unless a command is given (it reads the file on its standard input).
    config.x.document_virus_scan = ENV["DOCUMENT_VIRUS_SCAN_COMMAND"].presence&.then do |command|
      { command: Shellwords.split(command), fail_open: ENV["DOCUMENT_VIRUS_SCAN_FAIL_OPEN"] == "true" }
    end

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Use structure.sql to preserve PG triggers/functions that schema.rb drops.
    config.active_record.schema_format = :sql

    config.i18n.default_locale = :en
  end
end

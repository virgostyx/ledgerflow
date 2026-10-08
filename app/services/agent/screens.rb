# The screens of the application that a correction can point to (A08): a name, the label a person reads, and the path. The playbooks and the finding context name a screen by `screen:name`; the application makes
# the link from this table, like any other reference, so that a step of a correction never points to a screen that does not exist.
module Agent::Screens
  TABLE = {
    "lettering"     => [ "Lettering", ->(routes) { routes.new_accounting_lettering_path } ],
    "journal"       => [ "Journal entries", ->(routes) { routes.accounting_journal_entries_path } ],
    "sales"         => [ "Sales invoices", ->(routes) { routes.accounting_sales_path } ],
    "purchases"     => [ "Purchase invoices", ->(routes) { routes.accounting_purchases_path } ],
    "partners"      => [ "Partners", ->(routes) { routes.accounting_partners_path } ],
    "accounts"      => [ "Chart of accounts", ->(routes) { routes.accounting_settings_accounts_path } ],
    "documents"     => [ "Documents", ->(routes) { routes.accounting_documents_path } ],
    "bank"          => [ "Bank statements", ->(routes) { routes.accounting_bank_statements_path } ],
    "imports"       => [ "Imports", ->(routes) { routes.accounting_imports_path } ],
    "vat"           => [ "VAT returns", ->(routes) { routes.accounting_vat_declarations_path } ],
    "listing"       => [ "Intra-Community listings", ->(routes) { routes.accounting_intracom_listings_path } ],
    "periods"       => [ "Periods", ->(routes) { routes.accounting_period_locks_path } ],
    "fiscal_years"  => [ "Fiscal years", ->(routes) { routes.accounting_fiscal_years_path } ],
    "accruals"      => [ "Regularizations", ->(routes) { routes.accounting_accruals_path } ],
    "fixed_assets"  => [ "Fixed assets", ->(routes) { routes.accounting_fixed_assets_path } ],
    "tasks"         => [ "Tasks", ->(routes) { routes.accounting_tasks_path } ],
    "peppol"        => [ "Received invoices", ->(routes) { routes.accounting_peppol_messages_path } ],
    "cash_forecast" => [ "Cash forecast", ->(routes) { routes.accounting_reports_cash_forecast_path } ],
    "aged_balance"  => [ "Aged balance", ->(routes) { routes.accounting_reports_aged_balance_path } ],
    "consistency"   => [ "Consistency checks", ->(routes) { routes.accounting_consistency_runs_path } ]
  }.freeze

  def self.names = TABLE.keys
  def self.label(name) = TABLE[name]&.first
  def self.path(name) = TABLE[name]&.last&.call(Rails.application.routes.url_helpers)
  def self.ref(name) = Agent::Refs.build("screen", name)
end

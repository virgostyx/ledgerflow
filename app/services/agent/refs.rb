# The references the tools put on every value worth citing (A02, A05): `type:scope:key`, short and stable, and the screen each one opens. The model copies them into its
# answer; only the application turns them into links, from this table, never from an address the model wrote. A reference that is not here opens nothing.
module Agent::Refs
  PATHS = {
    "entry"   => ->(routes, id)            { routes.accounting_journal_entry_path(id) },
    "partner" => ->(routes, id)            { routes.accounting_partner_path(id) },
    "account" => ->(routes, id)            { routes.accounting_settings_account_path(id) },
    "doc"     => ->(routes, id)            { routes.accounting_document_path(id) },
    "vat"     => ->(routes, id)            { routes.accounting_vat_declaration_path(id) },
    "audit"   => ->(routes, id)            { routes.accounting_audit_log_path(id) },
    "R01"     => ->(routes, fiscal_year, as_of, *)     { routes.accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year, as_of: as_of) },
    "R02"     => ->(routes, fiscal_year, account, range, *) { routes.accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year, account_id: account, date_from: range.to_s.split("..").first, date_to: range.to_s.split("..").last) },
    "R04"     => ->(routes, as_of, kind, *)            { routes.accounting_reports_aged_balance_path(kind: kind, as_of: as_of) },
    "R05"     => ->(routes, as_of, kind, *)            { routes.accounting_reports_unlettered_lines_path(kind: kind, as_of: as_of) },
    "R06"     => ->(routes, bank_account, as_of, *)    { routes.accounting_reports_bank_reconciliation_report_path(bank_account_id: bank_account, as_of: as_of) },
    "R07"     => ->(routes, fiscal_year, *)            { routes.accounting_reports_balance_sheet_path(fiscal_year_id: fiscal_year) },
    "R08"     => ->(routes, fiscal_year, *)            { routes.accounting_reports_income_statement_path(fiscal_year_id: fiscal_year) },
    "R09"     => ->(routes, *)                         { routes.accounting_vat_declarations_path },
    "R19"     => ->(routes, *)             { routes.accounting_consistency_runs_path },
    "kpi"     => ->(routes, *)             { routes.accounting_root_path }
  }.freeze

  def self.build(type, *parts) = [ type, *parts ].map(&:to_s).join(":")

  # The path a reference opens, or nil for a reference this table does not know (a forged or mistyped one).
  def self.path(ref)
    type, *parts = ref.to_s.split(":", -1)
    builder = PATHS[type]
    builder && parts.any? ? builder.call(Rails.application.routes.url_helpers, *parts) : nil
  rescue ArgumentError, ActionController::UrlGenerationError
    nil
  end

  # Every value in a tool result that is a reference, wherever it sits.
  def self.in_result(value)
    case value
    when Hash  then value.flat_map { |key, inner| key.to_s == "ref" && inner.is_a?(String) ? [ inner ] : in_result(inner) }
    when Array then value.flat_map { |inner| in_result(inner) }
    else []
    end
  end
end

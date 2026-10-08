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
    "note"    => ->(routes, id)            { routes.edit_agent_memory_note_path(id) },
    "screen"  => ->(routes, name)          { Agent::Screens.path(name) },
    "kb"      => ->(routes, doc, passage = nil) { (id = doc[/\Adoc-(\d+)\z/, 1]) && routes.agent_knowledge_document_path(id, anchor: passage && passage[/\Ap-\d+\z/]) },
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

  # A calculation of the agent has a reference too (calc:…) so that its result can be cited, but there is no screen to open: it is its inputs, each cited, that can be looked at.
  def self.computed?(ref) = ref.to_s.start_with?("calc:")

  # What a reference stands for, in words, from its parts alone (no lookup: it is shown on hover and in the list of sources).
  def self.label(ref)
    type, *parts = ref.to_s.split(":", -1)
    case type
    when "entry"   then "Entry ##{parts[0]}"
    when "partner" then "Partner ##{parts[0]}"
    when "account" then "Account ##{parts[0]}"
    when "doc"     then "Document ##{parts[0]}"
    when "vat"     then "VAT declaration ##{parts[0]}"
    when "audit"   then "Audit event ##{parts[0]}"
    when "note"    then "Case note ##{parts[0]}"
    when "screen"  then Agent::Screens.label(parts[0]) && "Screen: #{Agent::Screens.label(parts[0])}"
    when "kb"      then [ "Knowledge base, document ##{parts[0].to_s.delete_prefix('doc-')}", ("passage #{parts[1].to_s.delete_prefix('p-')}" if parts[1]) ].compact.join(", ")
    when "R01"     then "Trial balance as of #{parts[1]}"
    when "R02"     then "Ledger of account ##{parts[1]}, #{parts[2].to_s.sub('..', ' to ')}"
    when "R04"     then "Aged balance (#{parts[1]}s) as of #{parts[0]}, #{parts[2] == 'total' ? 'total' : "partner #{parts[2]}"}"
    when "R05"     then "Open lines (#{parts[1]}) as of #{parts[0]}"
    when "R06"     then "Bank reconciliation of account ##{parts[0]} as of #{parts[1]}"
    when "R07"     then "Balance sheet, fiscal year ##{parts[0]}"
    when "R08"     then "Income statement, fiscal year ##{parts[0]}"
    when "R09"     then "VAT grids #{parts[1].to_s.sub('..', ' to ')}"
    when "R19"     then "Consistency findings"
    when "kpi"     then "Indicator #{parts[0].to_s.tr('_', ' ')}"
    when "calc"    then "Calculation"
    end
  end

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

# One entry with its lines (A02), found by its reference or its identifier. A person limited to some journals gets nothing from the others.
class Agent::Tools::GetJournalEntry < Agent::Tools::Base
  tool_name "get_journal_entry"
  description "Returns one journal entry: its date, reference, description, status, journal and fiscal year, its lines (account, partner, debit, credit, label, VAT code, due date) and its totals. " \
              "Use it to explain or check a particular entry, given its reference (such as an invoice number or a journal sequence) or an entry reference from another result. " \
              "Do not use it to search many entries or to get balances: use the ledger or the trial balance."
  permission "records.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { reference: { type: "string", maxLength: 40, description: "The reference of the entry, exactly as written." },
                             id: { type: "integer", minimum: 1, description: "The identifier from an entry reference (entry:ID) of a previous result." } }
  classify "data.*.description" => :free_text, "data.*.lines.*.label" => :free_text, "data.*.lines.*.partner" => :personal,
           "data.*.lines.*.account_label" => :public_ref, "data.*.lines.*.account" => :public_ref

  def call(args, context)
    raise Agent::ToolError.new("invalid_arguments", "Give a reference or an id.") if args["reference"].blank? && args["id"].blank?

    entry = (args["id"] ? Accounting::JournalEntry.find_by(id: args["id"]) : Accounting::JournalEntry.where(reference: args["reference"]).order(:id).first)
    raise Agent::ToolError.new("not_found", "No entry found for these criteria.") unless entry

    forbid_journal!(context, entry.journal_id)
    lines = entry.lines.includes(:account, :partner).order(:sort_order, :id)
    Agent::ToolResult.build(
      data: [ { "reference" => entry.reference, "date" => entry.entry_date.iso8601, "description" => entry.description, "status" => entry.status,
                "journal" => entry.journal.code, "fiscal_year" => entry.fiscal_year.year, "reversal_of" => (Agent::Refs.build("entry", entry.reversal_of_id) if entry.reversal_of_id),
                "lines" => lines.map { |line| line_row(line) }, "ref" => Agent::Refs.build("entry", entry.id) } ],
      totals: { "debit" => money(lines.sum(:debit)), "credit" => money(lines.sum(:credit)), "ref" => Agent::Refs.build("entry", entry.id) },
      currency: "EUR", as_of: entry.entry_date, filters_applied: args.slice("reference", "id")
    )
  end

  private

  def line_row(line)
    { "account" => line.account.code, "account_label" => line.account.label_fr, "partner" => line.partner&.name, "debit" => money(line.debit), "credit" => money(line.credit),
      "label" => line.label, "vat_code" => line.vat_code, "due_date" => line.due_date&.iso8601, "lettered" => line.lettering_id.present? }
  end
end

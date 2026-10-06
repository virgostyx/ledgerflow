# The open lines of customers and suppliers, one by one (A02, R05): what is still to be lettered, with its age.
class Agent::Tools::ListUnreconciled < Agent::Tools::Base
  tool_name "list_unreconciled"
  description "Lists the open (unlettered) lines on customer and supplier accounts at a date, one row per line: partner, entry reference, due date, residual amount and age in days. " \
              "Use it to see which invoices or payments are still open, for one partner or for all, or the oldest ones. " \
              "Do not use it for totals per partner (use get_aged_balance) or for a whole account (use get_ledger)."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { kind: { type: "string", enum: %w[customer supplier both], description: "Default both." },
                             as_of: { type: "string", format: "date", description: "Open at this date (default: today)." },
                             min_age_days: { type: "integer", minimum: 0, maximum: 3650, description: "Only lines overdue by at least this many days." },
                             partner_id: { type: "integer", minimum: 1, description: "Only this partner: the ID of a partner reference (partner:ID)." } }.merge(paging(max: 100))
  classify "data.*.partner" => :personal, "data.*.reference" => :public_ref

  def call(args, context)
    kind = (args["kind"] || "both").to_sym
    as_of = date_arg(args, "as_of", context.today)
    rows = Accounting::UnletteredLinesQuery.new(kind: kind, as_of: as_of, min_age_days: args["min_age_days"]).call
    rows = rows.select { |row| row.partner_id == args["partner_id"] } if args["partner_id"]
    page_rows, next_cursor = page(rows, args, default: 25, max: 100)
    Agent::ToolResult.build(
      data: page_rows.map { |row| row_for(row) },
      totals: { "residual" => money(rows.sum(&:residual)), "lines" => rows.size.to_s, "ref" => Agent::Refs.build("R05", as_of, kind) },
      currency: "EUR", as_of: as_of, next_cursor: next_cursor,
      filters_applied: { "kind" => kind.to_s, "as_of" => as_of.iso8601, "min_age_days" => args["min_age_days"], "partner_id" => args["partner_id"], "entries" => "validated only" }.compact
    )
  end

  private

  def row_for(row)
    { "partner" => row.partner_name, "account" => row.account_code, "date" => row.entry_date.iso8601, "journal" => row.journal_code, "reference" => row.reference,
      "due_date" => row.due_date.iso8601, "debit" => money(row.debit), "credit" => money(row.credit), "residual" => money(row.residual), "age_days" => row.age_days,
      "ref" => Agent::Refs.build("entry", row.journal_entry_id) }
  end
end

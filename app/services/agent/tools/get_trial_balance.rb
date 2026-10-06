# The trial balance of a period (A02, R01): per account, the opening, the movements of the period and the closing. Validated entries only.
class Agent::Tools::GetTrialBalance < Agent::Tools::Base
  tool_name "get_trial_balance"
  description "Returns the trial balance: for each account that moved, the opening balance, the debit and credit movements of the period and the closing balance, with the totals. " \
              "Use it for the balance of an account or a family of accounts at a date, or to see where the movements are. Validated entries only; drafts are not included. " \
              "Do not use it to list the entries behind a balance (use get_ledger) or for customers' and suppliers' open amounts (use get_aged_balance)."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { fiscal_year: { type: "integer", minimum: 1900, maximum: 2200, description: "The fiscal year, by its year number (default: the current one)." },
                             as_of: { type: "string", format: "date", description: "Balance at this date, YYYY-MM-DD (default: today, or the end of the year)." },
                             date_from: { type: "string", format: "date", description: "Start of the period shown; what is before is the opening balance (default: start of the year)." },
                             account_prefix: { type: "string", pattern: "^\\d{1,10}$", maxLength: 10, description: "Only accounts whose code starts with these digits, e.g. 40 for customers." } }.merge(paging(max: 100))
  classify "data.*.label" => :public_ref, "data.*.code" => :public_ref

  def call(args, context)
    year = fiscal_year_from(args)
    as_of = date_arg(args, "as_of", [ context.today, year.end_date ].min)
    from = date_arg(args, "date_from", year.start_date)
    raise Agent::ToolError.new("invalid_arguments", "date_from must not be after as_of.") if from > as_of

    rows = Accounting::TrialBalanceQuery.new(fiscal_year: year, as_of: as_of, date_from: from).call
    rows = rows.select { |row| row.code.start_with?(args["account_prefix"]) } if args["account_prefix"]
    page_rows, next_cursor = page(rows, args, default: 50, max: 100)
    Agent::ToolResult.build(
      data: page_rows.map { |row| row_for(row, year, from, as_of) },
      totals: totals(rows).merge("ref" => Agent::Refs.build("R01", year.id, as_of)),
      currency: "EUR", as_of: as_of, next_cursor: next_cursor,
      filters_applied: { "fiscal_year" => year.year, "date_from" => from.iso8601, "as_of" => as_of.iso8601, "account_prefix" => args["account_prefix"], "entries" => "validated only" }.compact,
      warnings: warnings(rows, year, args)
    )
  end

  private

  def row_for(row, year, from, as_of)
    { "code" => row.code, "label" => row.label_fr, "type" => row.account_type,
      "opening_debit" => money(row.opening_display_debit), "opening_credit" => money(row.opening_display_credit),
      "movement_debit" => money(row.movement_debit), "movement_credit" => money(row.movement_credit),
      "closing_debit" => money(row.closing_display_debit), "closing_credit" => money(row.closing_display_credit),
      "ref" => Agent::Refs.build("R02", year.id, row.id, "#{from.iso8601}..#{as_of.iso8601}") }
  end

  # Sums of the account rows the report already aggregated in SQL; never of entry lines.
  def totals(rows)
    { "opening_debit" => money(rows.sum(&:opening_display_debit)), "opening_credit" => money(rows.sum(&:opening_display_credit)),
      "movement_debit" => money(rows.sum(&:movement_debit)), "movement_credit" => money(rows.sum(&:movement_credit)),
      "closing_debit" => money(rows.sum(&:closing_display_debit)), "closing_credit" => money(rows.sum(&:closing_display_credit)) }
  end

  # Only a whole trial balance must balance: a family of accounts does not.
  def warnings(rows, year, args)
    notes = []
    notes << "The trial balance does not balance: closing debit and credit differ. See the consistency findings." if args["account_prefix"].nil? && rows.sum(&:closing_net).nonzero?
    notes << "The fiscal year #{year.year} is not closed: these figures can still change." unless year.closed?
    notes
  end
end

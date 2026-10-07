# The annual accounts in the abridged Belgian model (A02, R07, R08): the assets, the liabilities or the income statement by legal heading, next to the previous year.
class Agent::Tools::GetFinancialStatements < Agent::Tools::Base
  tool_name "get_financial_statements"
  description "Returns one statement of the annual accounts of a fiscal year, by legal heading: the assets, the liabilities or the income statement, each heading with its amount, the previous year's amount and the variation. " \
              "Use it to compare years, to read the result, the equity or the structure of the balance sheet. Validated entries only. " \
              "Do not use it for an account's balance (use get_trial_balance) or for the lines behind a figure (use get_ledger)."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[statement],
               properties: { statement: { type: "string", enum: %w[assets liabilities income], description: "assets and liabilities make the balance sheet." },
                             fiscal_year: { type: "integer", minimum: 1900, maximum: 2200, description: "The fiscal year, by its year number (default: the current one)." },
                             as_of: { type: "string", format: "date", description: "A situation inside the year, at this date (default: the whole year)." } }.merge(paging(max: 100))
  classify "data.*.label" => :public_ref, "data.*.code" => :public_ref

  def call(args, _context)
    year = fiscal_year_from(args)
    statement = args["statement"].to_sym
    report = Accounting::AnnualAccounts.new(fiscal_year: year, as_of: (Date.iso8601(args["as_of"]) if args["as_of"])).call
    rows, next_cursor = page(report.rows(statement), args, default: 60, max: 100)
    ref = Agent::Refs.build(statement == :income ? "R08" : "R07", year.id)
    Agent::ToolResult.build(
      data: rows.map { |row| row_for(row, ref) },
      totals: { "balance_sheet_difference" => money(report.difference), "balanced" => report.balanced?.to_s, "ref" => ref },
      currency: "EUR", as_of: args["as_of"] ? Date.iso8601(args["as_of"]) : year.end_date, next_cursor: next_cursor,
      filters_applied: { "statement" => args["statement"], "fiscal_year" => year.year, "previous_fiscal_year" => report.previous_year&.year, "as_of" => args["as_of"], "entries" => "validated only" }.compact,
      warnings: warnings(report, year)
    )
  end

  private

  def row_for(row, ref)
    { "code" => row.code, "label" => row.label, "level" => row.level, "amount" => money(row.amount), "previous" => (money(row.previous) unless row.previous.nil?),
      "variation_amount" => (money(row.variation_amount) unless row.variation_amount.nil?), "variation_percent" => row.variation_pct&.to_s("F"), "ref" => ref }.compact
  end

  def warnings(report, year)
    notes = []
    notes << "The fiscal year #{year.year} is not closed: these figures can still change." unless year.closed?
    notes << "The balance sheet does not balance (difference #{money(report.difference)} EUR). See the consistency findings." unless report.balanced?
    notes << "#{report.unmapped.size} account(s) are not mapped to a heading of the annual accounts, so their balance is missing from the statements: #{report.unmapped.first(5).map { |account| "#{account.code} (#{account.label}, balance #{money(account.balance)})" }.join('; ')}." if report.unmapped.any?
    previous = report.previous_year
    notes << "The previous fiscal year does not have the same length (#{(previous.end_date - previous.start_date).to_i + 1} days against #{(year.end_date - year.start_date).to_i + 1}): compare with care." if previous && (previous.end_date - previous.start_date) != (year.end_date - year.start_date)
    notes
  end
end

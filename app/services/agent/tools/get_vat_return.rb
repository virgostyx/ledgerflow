# The VAT grids of a period (A02, R09): the amount in each grid of the return, from the validated entries. It reads; it never prepares or files a declaration.
class Agent::Tools::GetVatReturn < Agent::Tools::Base
  tool_name "get_vat_return"
  description "Returns the amounts of the VAT return grids for a period, from the validated entries, with the declarations already prepared for that period and their status. " \
              "Use it to say what VAT is due or recoverable for a month or a quarter, or what is in a grid. " \
              "Do not use it to prepare or file a return (the agent cannot), or for the balance of the VAT accounts (use get_trial_balance with prefix 45 or 41)."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[period_start period_end],
               properties: { period_start: { type: "string", format: "date", description: "First day of the period, YYYY-MM-DD." },
                             period_end: { type: "string", format: "date", description: "Last day of the period, YYYY-MM-DD." },
                             fiscal_year: { type: "integer", minimum: 1900, maximum: 2200, description: "The fiscal year, by its year number (default: the one holding the period)." } }
  classify "data.*.grid" => :public_ref

  def call(args, _context)
    from, to = Date.iso8601(args["period_start"]), Date.iso8601(args["period_end"])
    raise Agent::ToolError.new("invalid_arguments", "period_start must not be after period_end.") if from > to

    year = args["fiscal_year"] ? fiscal_year_from(args) : (Accounting::FiscalYear.where("start_date <= ? AND end_date >= ?", from, from).first || fiscal_year_from({}))
    grids = Accounting::VatGridQuery.call(fiscal_year_id: year.id, period_start: from, period_end: to)
    ref = Agent::Refs.build("R09", year.id, "#{from.iso8601}..#{to.iso8601}")
    Agent::ToolResult.build(
      data: grids.map { |grid, amount| { "grid" => grid, "amount" => money(amount), "ref" => ref } },
      totals: { "declarations" => declarations(year, from, to), "ref" => ref },
      currency: "EUR", as_of: to,
      filters_applied: { "fiscal_year" => year.year, "period_start" => from.iso8601, "period_end" => to.iso8601, "entries" => "validated only" },
      warnings: grids.empty? ? [ "No VAT movement in this period." ] : []
    )
  end

  private

  def declarations(year, from, to)
    Accounting::VatDeclaration.where(fiscal_year_id: year.id).where("period_start <= ? AND period_end >= ?", to, from).order(:period_start)
                              .map { |declaration| { "period" => "#{declaration.period_start.iso8601}..#{declaration.period_end.iso8601}", "status" => declaration.status, "ref" => Agent::Refs.build("vat", declaration.id) } }
  end
end

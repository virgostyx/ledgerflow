# The indicators of the dashboard (A02, R13): cash, revenue, margin, fixed costs, result, DSO, DPO, working capital, overdue receivables, cash coverage. Each one comes from a report.
class Agent::Tools::GetDashboardKpis < Agent::Tools::Base
  KEYS = Accounting::DashboardKpis::DEFINITIONS.map { |key, *| key.to_s }.freeze

  tool_name "get_dashboard_kpis"
  description "Returns the key indicators of the dashboard at a date: available cash, revenue year to date, gross margin, monthly fixed costs, result year to date, DSO, DPO, working capital requirement, overdue receivables and cash coverage, " \
              "each with its formula and its status. Use it for a quick picture of how the entity is doing. " \
              "Do not use it when the exact figure of a report is needed, or for a detail behind an indicator: use the report tool the formula points to."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { kpi: { type: "string", enum: KEYS, description: "One indicator (default: all)." },
                             fiscal_year: { type: "integer", minimum: 1900, maximum: 2200, description: "The fiscal year, by its year number (default: the current one)." },
                             as_of: { type: "string", format: "date", description: "At this date (default: today)." } }
  classify "data.*.label" => :public_ref

  def call(args, context)
    year = fiscal_year_from(args)
    as_of = date_arg(args, "as_of", context.today)
    cards = Accounting::DashboardKpis.new(fiscal_year: year, as_of: as_of).call(only: (args["kpi"] ? [ args["kpi"].to_sym ] : nil))
    Agent::ToolResult.build(
      data: cards.map { |card| row_for(card) }, currency: "EUR", as_of: [ as_of, year.end_date ].min,
      filters_applied: { "fiscal_year" => year.year, "as_of" => as_of.iso8601, "kpi" => args["kpi"], "entries" => "validated only" }.compact,
      warnings: Array(("The fiscal year #{year.year} is not closed: these figures can still change." unless year.closed?))
    )
  end

  private

  def row_for(card)
    value = card.value.nil? ? nil : (card.unit == :money ? money(card.value) : card.value.to_d.round(1).to_s("F"))
    { "key" => card.key.to_s, "label" => card.label, "unit" => card.unit.to_s, "value" => value, "formula" => card.formula, "status" => card.status.to_s, "error" => card.error,
      "ref" => Agent::Refs.build("kpi", card.key) }.compact
  end
end

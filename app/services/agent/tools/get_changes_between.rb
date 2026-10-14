# What changed in the books between two moments (B03b, R21): the counts, the accounts that moved most, the alerts a reviewer looks at first, and the closing of the figures.
class Agent::Tools::GetChangesBetween < Agent::Tools::Base
  tool_name "get_changes_between"
  description "What changed in the books between two moments: counts of entries, reversals, letterings, locks, accounts that moved most, alerts, closing. " \
              "For 'what changed since yesterday?'. Not for a balance (get_trial_balance) or an account's entries (get_ledger)."
  permission "time_travel.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[from],
               properties: { from: { type: "string", maxLength: 40, description: "Moment T1 (ISO 8601)." },
                             to: { type: "string", maxLength: 40, description: "Moment T2 (default now)." },
                             fiscal_year: { type: "integer", minimum: 1900, maximum: 2200, description: "Fiscal year (default current)." },
                             limit: { type: "integer", minimum: 1, maximum: 20, description: "Accounts shown (default 10)." } }
  classify "data.*.label" => :public_ref, "data.*.code" => :public_ref

  def call(args, context)
    raise Agent::ToolError.new("forbidden", "What changed is not available for this entity or this person.") unless context.entity.feature?(:b03a) && context.entity.feature?(:b03b)

    year = fiscal_year_from(args)
    report = changes_report(args, year)
    rows = report.impact.sort_by { |r| -r.variation.abs }.first(args["limit"] || 10)
    Agent::ToolResult.build(
      data: rows.map { |r| { "code" => r.code, "label" => r.label, "at_from" => money(r.at_t1), "at_to" => money(r.at_t2), "variation" => money(r.variation), "movements" => money(r.movements) } },
      totals: report.summary.to_h.transform_keys(&:to_s).transform_values(&:to_s).merge("ref" => Agent::Refs.build("R21", year.id, report.from.to_i)),
      currency: "EUR", as_of: report.as_of,
      filters_applied: { "fiscal_year" => year.year, "from" => report.from.utc.iso8601, "to" => (report.to || Time.current).utc.iso8601 },
      warnings: [ I18n.t("changes.closing.#{report.closing.balanced? ? 'balanced' : 'gap'}", gap: format("%.2f", report.closing.gap)) ] + report.alerts.map { |a| "Alert: #{a.kind.to_s.tr('_', ' ')}" }.tally.map { |text, n| "#{text} (#{n})" }
    )
  end
end

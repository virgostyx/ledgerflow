# Immutable output of every report (docs/dev/reports/spec.md §2.1). Exporters
# and ViewComponents consume only this — never the query directly.
Reports::Result = Data.define(:rows, :totals, :filters, :generated_at, :currency, :warnings) do
  def initialize(rows:, totals: {}, filters: nil, generated_at: Time.current, currency: "EUR", warnings: [])
    super
  end
end

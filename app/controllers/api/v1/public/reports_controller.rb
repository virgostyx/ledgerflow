# F13c: reports as JSON, the Reports::Result the screens and the exports are made from (so the figures are the same ones).
class Api::V1::Public::ReportsController < Api::V1::Public::BaseController
  REPORTS = %w[trial_balance aged_balance].freeze

  self.action_scopes = { show: "reports:read" }

  def show
    name = params[:name].to_s
    return problem(:not_found, "Not found", detail: "Known reports: #{REPORTS.join(', ')}.", slug: "not-found") unless REPORTS.include?(name)

    result = send(name)
    return if performed?

    render json: { data: { report: name, currency: result.currency, generated_at: result.generated_at.iso8601, filters: result.filters&.as_json, warnings: result.warnings,
                           totals: dump(result.totals), rows: result.rows.map { |row| dump(row) } } }
  end

  private

  def trial_balance
    year = params[:fiscal_year].present? ? Accounting::FiscalYear.find_by!(year: params[:fiscal_year]) : Accounting::FiscalYear.current
    return problem(:not_found, "Not found", detail: "No open fiscal year: give fiscal_year.", slug: "not-found") unless year

    filters = Reports::Filters.new(fiscal_year_id: year.id, date_to: date_param(:as_of) || year.end_date)
    Accounting::TrialBalanceReport.new(filters: filters).call
  end

  def aged_balance
    kind = params[:kind] == "supplier" ? :supplier : :customer
    as_of = date_param(:as_of) || Date.current
    rows = Accounting::AgedBalanceQuery.new(kind: kind, as_of: as_of).call
    Reports::Result.new(rows: rows, totals: Accounting::AgedBalanceQuery.totals(rows), filters: { kind: kind, as_of: as_of.iso8601 })
  end

  def date_param(key) = params[key].present? ? Date.iso8601(params[key].to_s) : nil

  # A row or a total: a Struct, a Hash or a wrapper of one; amounts as text, dates in ISO.
  def dump(value)
    value = value.row if value.respond_to?(:row) && !value.is_a?(Hash)
    hash = value.respond_to?(:to_h) ? value.to_h : value.as_json
    hash.transform_values { |v| Api::V1::Resources.value(v) }.transform_keys(&:to_s)
  end
end

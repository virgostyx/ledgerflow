# F13c: reports as JSON, the Reports::Result the screens and the exports are made from (so the figures are the same ones).
class Api::V1::Public::ReportsController < Api::V1::Public::BaseController
  REPORTS = %w[trial_balance aged_balance].freeze

  self.action_scopes = { show: "reports:read" }
  HISTORICAL = %w[trial_balance].freeze # B03a: the reports that can be read as known at an instant (`known_at`, ISO 8601 with its offset)

  rescue_from(Accounting::KnownAt::Invalid) { |e| problem(:bad_request, "Invalid instant", detail: e.message, slug: "invalid-instant") }
  rescue_from(Accounting::KnownAt::Refused) { |e| problem(:unprocessable_content, "Before the history", detail: e.message, slug: "before-history", code: "before_history_start") }

  def show
    name = params[:name].to_s
    return problem(:not_found, "Not found", detail: "Known reports: #{REPORTS.join(', ')}.", slug: "not-found") unless REPORTS.include?(name)

    return problem(:unprocessable_content, "Not available", detail: I18n.t("accounting.known_at.not_available"), slug: "historical-view-not-available") if params[:known_at].present? && HISTORICAL.exclude?(name)

    return problem(:forbidden, "Forbidden", detail: "The historical view is off, or not allowed to the owner of this token.", slug: "historical-view-forbidden") if params[:known_at].present? && !historical_allowed?

    result = send(name)
    return if performed?

    render json: { data: { report: name, currency: result.currency, generated_at: result.generated_at.iso8601, filters: result.filters&.as_json, warnings: result.warnings,
                           totals: dump(result.totals), rows: result.rows.map { |row| dump(row) } } }
  end

  private

  def historical_allowed? = ActsAsTenant.current_tenant.feature?(:b03a) && Accounting::ReportPolicy.new(Current.user, :report).time_travel?

  def trial_balance
    year = params[:fiscal_year].present? ? Accounting::FiscalYear.find_by!(year: params[:fiscal_year]) : Accounting::FiscalYear.current
    return problem(:not_found, "Not found", detail: "No open fiscal year: give fiscal_year.", slug: "not-found") unless year

    filters = Reports::Filters.new(fiscal_year_id: year.id, date_to: date_param(:as_of) || year.end_date, known_at: (Accounting::KnownAt.parse(params[:known_at]) if params[:known_at].present?))
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

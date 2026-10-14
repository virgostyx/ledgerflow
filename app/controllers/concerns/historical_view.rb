# B03a: a screen that can show the books as they were known at an instant (`known_at`). The instant comes from the query; today's view is any instant that is now or later.
# A screen lists the actions it supports with `historical_actions`; on any other, or on an instant before the start of the history, the person is sent back to today's view
# with the reason. `known_at` is the Accounting::KnownAt in force, nil in today's view.
module HistoricalView
  extend ActiveSupport::Concern

  included do
    class_attribute :historical_actions, default: []
    before_action :set_known_at
    helper_method :known_at, :historical_view?, :historical_params
  end

  private

  attr_reader :known_at

  def historical_view? = known_at.present?

  # The query to carry on every link of a historical view.
  def historical_params = historical_view? ? { known_at: known_at.time.utc.iso8601(6) } : {}

  def set_known_at
    return if params[:known_at].blank?
    return back_to_today(t("accounting.known_at.not_available")) unless historical_actions.include?(action_name.to_sym)

    return back_to_today(t("errors.feature_off")) unless feature?(:b03a)

    authorize :report, :time_travel?, policy_class: Accounting::ReportPolicy
    candidate = Accounting::KnownAt.new(Accounting::KnownAt.parse(params[:known_at]), fiscal_year: @fiscal_year)
    return back_to_today(candidate.refusal) if candidate.refused?

    return if candidate.current?

    @known_at = candidate
    record_historical_view
  rescue Accounting::KnownAt::Invalid => e
    back_to_today(e.message)
  end

  # Who looked at the books as known when (R18): a view of the past is a reading worth keeping a trace of.
  def record_historical_view
    Accounting::AuditLog.record!(auditable: ActsAsTenant.current_tenant, action: "historical_view", user: current_user, payload: { report: action_name, known_at: known_at.time.utc.iso8601(6) })
  end

  def back_to_today(message)
    query = request.query_parameters.except("known_at").to_query
    redirect_to [ request.path, query.presence ].compact.join("?"), alert: message
  end
end

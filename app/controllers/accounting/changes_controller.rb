# B03b R21, the page "What changed": what the books gained between two moments (the instants of B03a), the impact on the figures, the detail, the alerts for a reviewer.
# Read only. The names of the authors need `audit.view`; marking a change as reviewed needs `changes.review`.
class Accounting::ChangesController < ApplicationController
  before_action -> { require_feature!(:b03a) }
  before_action -> { require_feature!(:b03b) }
  before_action :set_fiscal_year
  before_action(if: -> { %i[csv xlsx pdf].include?(request.format.symbol) }) { authorize :changes, :export?, policy_class: Accounting::ChangesPolicy }

  PRESETS = %w[yesterday_18 last_visit last_lock].freeze
  TABS = %w[impact detail alerts].freeze

  def index
    authorize :changes, :index?, policy_class: Accounting::ChangesPolicy

    @presets = presets
    @can_review = changes_policy.review?
    @can_export = changes_policy.export?
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "impact"
    @from, @to = instants
    @as_of = Date.iso8601(params[:as_of].to_s) rescue @fiscal_year.end_date # rubocop:disable Style/RescueModifier
    @result = build_report

    record_view
    respond_to do |format|
      format.html { Changes::Visit.record(current_user) unless params[:visit] == "erased" } # the page that says it was erased is not a visit
      format.csv  { export(:csv) }
      format.xlsx { export(:xlsx) }
      format.pdf  { export(:pdf) }
    end
  rescue Accounting::KnownAt::Refused, Accounting::KnownAt::Invalid, Changes::Between::Invalid => e
    @error = e.message
    render :index
  end

  def review
    authorize :changes, :review?, policy_class: Accounting::ChangesPolicy

    result = Changes::Review.call(key: params[:key].to_s, user: current_user, comment: params[:comment])
    redirect_to accounting_changes_path(params.permit(:fiscal_year_id, :from, :to, :as_of, :tab).to_h.merge(tab: "detail")),
                (result.success? ? { notice: t("changes.reviewed") } : { alert: result.message })
  end

  def erase_visit
    authorize :changes, :erase_visit?, policy_class: Accounting::ChangesPolicy

    Changes::Visit.erase(current_user)
    redirect_to accounting_changes_path(visit: "erased"), notice: t("changes.visit_erased")
  end

  private

  def changes_policy = @changes_policy ||= Accounting::ChangesPolicy.new(current_user, :changes)

  def set_fiscal_year = @fiscal_year = params[:fiscal_year_id].present? ? Accounting::FiscalYear.find(params[:fiscal_year_id]) : Accounting::FiscalYear.current

  def presets
    last_lock = Accounting::PeriodLock.maximum(:locked_at)
    {
      "yesterday_18" => Time.zone.yesterday.in_time_zone.change(hour: 18),
      "last_visit" => Changes::Visit.last(current_user),
      "last_lock" => last_lock&.in_time_zone
    }.compact
  end

  # T1 and T2: typed, from a preset, or by default since the last visit (else since yesterday 18:00). T2 is now unless given.
  def instants
    to = params[:to].present? ? Accounting::KnownAt.parse(params[:to]) : nil
    from = if params[:from].present?
      Accounting::KnownAt.parse(params[:from])
    else
      @presets[params[:preset]] || @presets["last_visit"] || @presets["yesterday_18"]
    end
    [ from, to ]
  end

  def build_report
    Changes::Report.call(fiscal_year: @fiscal_year, from: @from, to: @to, as_of: @as_of, show_authors: changes_policy.authors?, categories: params[:categories].presence,
                         hide_neutral: params[:hide_neutral] == "1", page: params[:page], per: (params[:format].present? ? nil : 100), journal_ids: params[:journal_ids].presence,
                         account_codes: params[:account_codes].presence, actor_ids: params[:actor_ids].presence&.map(&:to_i))
  end

  def record_view
    Accounting::AuditLog.record!(auditable: ActsAsTenant.current_tenant, action: "changes_report_viewed", user: current_user,
                                 payload: { from: @result.from&.utc&.iso8601(6), to: @result.to&.utc&.iso8601(6), as_of: @result.as_of, format: request.format.symbol })
  end

  # An official export leaves only when the closing is exact (I14).
  def export(format)
    unless Changes::ClosingGuard.call(@result, fiscal_year: @fiscal_year)
      return redirect_to accounting_changes_path(request.query_parameters.except("format")), alert: t("changes.export_blocked")
    end

    exported = Changes::Export.new(@result, fiscal_year: @fiscal_year, watermark: export_watermark)
    send_data exported.public_send(format), filename: exported.filename(format), type: Mime[format].to_s
  end
end

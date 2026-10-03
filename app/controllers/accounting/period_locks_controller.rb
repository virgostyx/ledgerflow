# F01: the periods whose entries can no longer be posted. Locking is for accountants and owners, unlocking
# (with a mandatory reason, announced to the owners) for owners only.
class Accounting::PeriodLocksController < ApplicationController
  before_action { require_feature!(:f01) }

  def index
    authorize Accounting::PeriodLock
    @locks = Accounting::PeriodLock.includes(:locked_by, :unlocked_by).order(starts_on: :desc, id: :desc)
    @lock  = Accounting::PeriodLock.new(kind: :accounting)
    @fiscal_years = Accounting::FiscalYear.order(year: :desc)
    @timeline = Accounting::PeriodTimeline.new(selected_fiscal_year) if selected_fiscal_year
  end

  # The grouped lock of the timeline: the months ticked, whole.
  def lock_months
    authorize Accounting::PeriodLock, :create?
    kind = Accounting::PeriodLock.kinds.key?(params[:kind]) ? params[:kind] : "accounting"
    result = Accounting::LockMonths.call(months: params[:months], kind: kind, reason: params[:reason].presence, user: current_user)
    if result.success?
      redirect_to accounting_period_locks_path(fiscal_year_id: selected_fiscal_year&.id), notice: t("accounting.period_locks.months_locked", count: result[:locked])
    else
      redirect_to accounting_period_locks_path(fiscal_year_id: selected_fiscal_year&.id), alert: result.message
    end
  end

  def create
    authorize Accounting::PeriodLock
    attrs = params.require(:period_lock).permit(:kind, :starts_on, :ends_on, :lock_reason)
    result = Accounting::LockPeriod.call(starts_on: attrs[:starts_on], ends_on: attrs[:ends_on], kind: attrs[:kind].presence || :accounting,
                                         reason: attrs[:lock_reason], user: current_user)
    if result.success?
      redirect_to accounting_period_locks_path, notice: t("accounting.period_locks.locked")
    else
      redirect_to accounting_period_locks_path, alert: result.message
    end
  end

  def unlock
    lock = Accounting::PeriodLock.find(params[:id])
    authorize lock, :unlock?
    hours = params[:hours].to_i
    result = Accounting::UnlockPeriod.call(lock: lock, reason: params[:reason], user: current_user, relock_at: (hours.hours.from_now if hours.positive?))
    if result.success?
      redirect_to accounting_period_locks_path, notice: t("accounting.period_locks.unlocked")
    else
      redirect_to accounting_period_locks_path, alert: result.message
    end
  end

  private

  # The year of the timeline: the one asked for, else the open one, else the latest.
  def selected_fiscal_year
    @selected_fiscal_year ||= Accounting::FiscalYear.find_by(id: params[:fiscal_year_id]) || Accounting::FiscalYear.current || Accounting::FiscalYear.order(:year).last
  end
end

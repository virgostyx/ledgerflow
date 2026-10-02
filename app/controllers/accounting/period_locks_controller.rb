# F01: the periods whose entries can no longer be posted. Locking is for accountants and owners, unlocking
# (with a mandatory reason, announced to the owners) for owners only.
class Accounting::PeriodLocksController < ApplicationController
  def index
    authorize Accounting::PeriodLock
    @locks = Accounting::PeriodLock.includes(:locked_by, :unlocked_by).order(starts_on: :desc, id: :desc)
    @lock  = Accounting::PeriodLock.new(kind: :accounting)
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
    result = Accounting::UnlockPeriod.call(lock: lock, reason: params[:reason], user: current_user)
    if result.success?
      redirect_to accounting_period_locks_path, notice: t("accounting.period_locks.unlocked")
    else
      redirect_to accounting_period_locks_path, alert: result.message
    end
  end
end

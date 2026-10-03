# Locks a range of accounting dates: no entry dated inside it can be posted until it is unlocked.
class Accounting::LockPeriod
  def self.call(starts_on:, ends_on:, user:, kind: :accounting, reason: nil)
    ctx = LightService::Context.make(lock: nil)
    ApplicationRecord.transaction do
      Accounting::PeriodLock.serialize_for_entity!
      if Accounting::PeriodLock.in_force.where(kind: kind).where("starts_on <= ? AND ends_on >= ?", starts_on, ends_on).exists?
        ctx.fail!(I18n.t("accounting.period_locks.already_locked"))
        raise ActiveRecord::Rollback
      end

      lock = Accounting::PeriodLock.create!(starts_on: starts_on, ends_on: ends_on, kind: kind, locked_by: user,
                                            locked_at: Time.current, lock_reason: reason.presence)
      Accounting::AuditLog.record!(auditable: lock, action: "lock_period", user: user, reason: reason.presence,
                                   payload: { kind: kind, starts_on: starts_on, ends_on: ends_on })
      ctx[:lock] = lock
    end
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.message)
    ctx
  end
end

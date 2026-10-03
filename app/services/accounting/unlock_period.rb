# Reopens a locked period. The reason is mandatory and goes to the audit trail. `relock_at:` makes the unlock temporary: the
# period closes again by itself at that time (Accounting::RelockPeriodsJob), at most MAX_HOURS ahead.
class Accounting::UnlockPeriod
  MAX_HOURS = 72

  def self.call(lock:, user:, reason:, relock_at: nil)
    ctx = LightService::Context.make(lock: lock)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.errors.unlock_reason_required")) } if reason.blank?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.errors.unlock_deadline_invalid", hours: MAX_HOURS)) } if relock_at && !(Time.current...MAX_HOURS.hours.from_now).cover?(relock_at)

    ApplicationRecord.transaction do
      lock.lock! # a second owner clicking at the same moment waits here, then finds it already unlocked
      unless lock.locked?
        ctx.fail!(I18n.t("accounting.errors.period_not_locked"))
        raise ActiveRecord::Rollback
      end

      lock.update!(status: :unlocked, unlocked_by: user, unlocked_at: Time.current, unlock_reason: reason, relock_at: relock_at)
      Accounting::AuditLog.record!(auditable: lock, action: "unlock_period", user: user, reason: reason,
                                   payload: { kind: lock.kind, starts_on: lock.starts_on, ends_on: lock.ends_on, relock_at: relock_at&.utc&.iso8601 }.compact)
    end
    notify_owners(lock) if ctx.success?
    ctx
  end

  # The owners of the entity are told whenever a locked period is reopened.
  def self.notify_owners(lock)
    User.where(id: UserEntity.current.admin.where(entity_id: lock.entity_id).select(:user_id))
        .find_each { |owner| Accounting::PeriodMailer.unlocked(owner, lock).deliver_later }
  end
  private_class_method :notify_owners
end

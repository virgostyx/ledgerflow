# Reopens a locked period. The reason is mandatory and goes to the audit trail.
class Accounting::UnlockPeriod
  def self.call(lock:, user:, reason:)
    ctx = LightService::Context.make(lock: lock)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.errors.unlock_reason_required")) } if reason.blank?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.errors.period_not_locked")) } unless lock.locked?

    ApplicationRecord.transaction do
      lock.update!(status: :unlocked, unlocked_by: user, unlocked_at: Time.current, unlock_reason: reason)
      Accounting::AuditLog.record!(auditable: lock, action: "unlock_period", user: user, reason: reason,
                                   payload: { kind: lock.kind, starts_on: lock.starts_on, ends_on: lock.ends_on })
    end
    notify_owners(lock)
    ctx
  end

  # The owners of the entity are told whenever a locked period is reopened.
  def self.notify_owners(lock)
    User.where(id: UserEntity.current.admin.where(entity_id: lock.entity_id).select(:user_id))
        .find_each { |owner| Accounting::PeriodMailer.unlocked(owner, lock).deliver_later }
  end
  private_class_method :notify_owners
end

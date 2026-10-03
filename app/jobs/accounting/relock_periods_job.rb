# Closes again the periods that were unlocked for a limited time (F01). The guards already treat them as locked from the
# deadline (Accounting::PeriodLock.in_force, the PostgreSQL functions); this puts the status and the audit trail right.
# Idempotent. => number of periods locked again
class Accounting::RelockPeriodsJob < ApplicationJob
  queue_as :default

  def perform
    ActsAsTenant.without_tenant { Accounting::PeriodLock.due_for_relock.to_a }.count do |lock|
      ActsAsTenant.with_tenant(Entity.find(lock.entity_id)) do
        lock.reload
        next false unless lock.unlocked? && lock.relock_at && lock.relock_at <= Time.current

        ApplicationRecord.transaction do
          lock.update!(status: :locked, relock_at: nil)
          Accounting::AuditLog.record!(auditable: lock, action: "relock_period", user: nil,
                                       payload: { kind: lock.kind, starts_on: lock.starts_on, ends_on: lock.ends_on, automatic: true })
        end
        true
      end
    end
  end
end

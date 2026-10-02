# F01: records a sign-in (or a failed one) in the audit trail of every entity the user can work in today, so
# each entity's auditor sees who connected, how, and who failed. A user who works in no entity leaves no trace here.
class Accounting::AuditLogin
  def self.call(user:, action:, method:, **details)
    entities = Entity.where(id: UserEntity.current.where(user_id: user.id).select(:entity_id))
    entities.find_each do |entity|
      ActsAsTenant.with_tenant(entity) do
        Accounting::AuditLog.record!(auditable: user, action: action, user: user, payload: { method: method }.merge(details))
      end
    end
  end
end

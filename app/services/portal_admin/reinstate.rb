# B02a: the firm lets a suspended person back in (their second factor and password stay as they were).
class PortalAdmin::Reinstate
  def self.call(person:, entity:, by:)
    person.update!(status: "active", last_sign_in_at: Time.current) # the clock of the dormancy starts again
    ActsAsTenant.with_tenant(entity) { Accounting::AuditLog.record!(auditable: person, action: "portal_user_reinstated", user: by) }
    LightService::Context.make
  end
end

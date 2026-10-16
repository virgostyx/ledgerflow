# B02a: the firm met or called the person, outside the portal: who can validate the accounts must have this on record.
class PortalAdmin::VerifyIdentity
  def self.call(person:, entity:, by:)
    person.update!(identity_verified_by: by, identity_verified_at: Time.current)
    ActsAsTenant.with_tenant(entity) { Accounting::AuditLog.record!(auditable: person, action: "portal_identity_verified", user: by) }
    LightService::Context.make
  end
end

# B02a: revokes one right of a person. It is effective at the next request (every request reads the grants); a person left with none loses their sessions.
class PortalAdmin::RevokeGrant
  def self.call(grant:, by:)
    result = LightService::Context.make
    ApplicationRecord.transaction do
      grant.update!(revoked_at: Time.current, revoked_by: by)
      person = grant.portal_user
      Portal::Session.revoke_all!(person) unless person.grants.in_force.exists?
      ActsAsTenant.with_tenant(Entity.find(grant.entity_id)) do
        Accounting::AuditLog.record!(auditable: person, action: "portal_grant_revoked", user: by, payload: { grant_id: grant.id, role: grant.role })
      end
    end
    result[:grant] = grant
    result
  end
end

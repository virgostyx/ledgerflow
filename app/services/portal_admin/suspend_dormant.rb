# B02a: whoever has not signed in for 180 days (from the creation of the account if never) is suspended, with their sessions. The firm reinstates on request.
class PortalAdmin::SuspendDormant
  DORMANT_AFTER = 180.days

  def self.call
    PortalUser.active.where("COALESCE(last_sign_in_at, created_at) < ?", DORMANT_AFTER.ago).find_each do |person|
      person.update!(status: "suspended")
      Portal::Session.revoke_all!(person)
      person.grants.in_force.pluck(:entity_id).uniq.each do |entity_id|
        ActsAsTenant.with_tenant(Entity.find(entity_id)) { Accounting::AuditLog.record!(auditable: person, action: "portal_user_suspended_dormant", payload: { days: DORMANT_AFTER.in_days.to_i }) }
      end
    end
  end
end

# B02a: a person lost their second factor. No recovery by e-mail alone: the firm wipes the factor and the password, ends the sessions and invites again.
class PortalAdmin::ResetAccess
  def self.call(person:, entity:, by:)
    result = LightService::Context.make
    grants = person.grants.in_force.where(entity_id: entity.id).to_a
    invitation = token = nil
    ApplicationRecord.transaction do
      person.backup_codes.destroy_all
      person.update!(status: "invited", totp_secret: nil, totp_enabled_at: nil, totp_last_step: nil, password: SecureRandom.base64(24), failed_attempts: 0, locked_at: nil)
      Portal::Session.revoke_all!(person)
      ActsAsTenant.with_tenant(entity) { Accounting::AuditLog.record!(auditable: person, action: "portal_access_reset", user: by, payload: { grants: grants.map(&:id) }) }
      role = grants.first&.role || "reader"
      capabilities = grants.first&.capabilities
      grants.each { |g| g.update!(revoked_at: Time.current, revoked_by: by) } # the new invitation writes them again
      invitation, token = Portal::Invitation.issue!(entity: entity, email: person.email, full_name: person.full_name, role: role, by: by, capabilities: capabilities)
      Portal::InvitationMailer.invite(invitation, token).deliver_now # at once and in the transaction: the token never goes through a job queue
    end
    result[:invitation] = invitation
    result
  end
end

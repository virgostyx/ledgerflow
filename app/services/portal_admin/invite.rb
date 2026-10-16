# B02a: the firm invites a person to the portal of a company. The right to do so (portal.manage) is checked by the caller.
class PortalAdmin::Invite
  SHARED_LOCAL_PARTS = %w[info contact comptabilite compta accounting admin office secretariat facturation invoices].freeze

  def self.call(entity:, email:, full_name:, role:, by:, capabilities: nil)
    result = LightService::Context.make
    invitation = nil
    # The e-mail goes out inside the transaction and at once (never through a job queue, which would keep the token): if it cannot be sent, nothing is kept.
    ApplicationRecord.transaction do
      invitation, token = Portal::Invitation.issue!(entity: entity, email: email, full_name: full_name, role: role, by: by, capabilities: capabilities)
      ActsAsTenant.with_tenant(entity) do
        Accounting::AuditLog.record!(auditable: invitation.portal_user, action: "portal_invited", user: by,
                                     payload: { email: invitation.email, role: role, capabilities: invitation.capabilities, invitation_id: invitation.id })
      end
      Portal::InvitationMailer.invite(invitation, token).deliver_now
    end
    result[:invitation] = invitation
    result[:warning] = "This looks like a shared address. Validations of the accounts need a personal identity: prefer a personal address." if shared?(invitation.email)
    result
  rescue ActiveRecord::RecordInvalid => e
    LightService::Context.make.tap { |r| r.fail!(e.record.errors.full_messages.to_sentence) }
  end

  def self.shared?(email) = SHARED_LOCAL_PARTS.include?(email.to_s.split("@").first.to_s.downcase)
end

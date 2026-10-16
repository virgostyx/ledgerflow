# The e-mails of the portal carry a link and no figure, no name of a third party (§2.5): who invites, and where to go.
class Portal::InvitationMailer < ApplicationMailer
  def invite(invitation, token)
    brand = Portal::Branding.find_by(entity_id: invitation.entity_id)
    @company_name = brand&.display_name || invitation.company.name
    @url = Rails.application.routes.url_helpers.portal_invitation_url(token, **Portal.url_options)
    @valid_days = Portal::INVITATION_VALIDITY.in_days.to_i
    mail from: (brand&.sender_name.present? ? email_address_with_name(default_params[:from], brand.sender_name) : default_params[:from]), to: invitation.email, subject: "#{@company_name} invites you to its client portal"
  end
end

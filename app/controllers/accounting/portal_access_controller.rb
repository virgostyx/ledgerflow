# B02a: the firm opens the client portal of the company to people from outside, and closes it again. Everything here is about the grants of this company.
class Accounting::PortalAccessController < ApplicationController
  before_action -> { require_feature!(:b02a) }
  before_action -> { authorize Accounting::PortalAccessPolicy, action_name.to_sym == :index ? :index? : "#{action_name}?".to_sym, policy_class: Accounting::PortalAccessPolicy }
  before_action :find_grant, only: %i[destroy reset verify_identity reinstate]
  before_action -> { require_recent_second_factor! }, only: :reset

  def index
    @grants = Portal::Grant.where(entity_id: current_entity_id).includes(:portal_user).order(:created_at)
    @brand = Portal::Branding.find_by(entity_id: current_entity_id)
    @review = PortalAdmin::AccessReview.call(entity: ActsAsTenant.current_tenant).index_by { |row| row.grant.id }
    @pending = Portal::Invitation.where(entity_id: current_entity_id, used_at: nil).where("expires_at > ?", Time.current).includes(:portal_user)
  end

  def create
    result = PortalAdmin::Invite.call(entity: ActsAsTenant.current_tenant, email: params[:email], full_name: params[:full_name], role: params[:role], by: current_user)
    if result.success?
      redirect_to accounting_portal_access_index_path, notice: [ "Invitation sent.", result[:warning] ].compact.join(" ")
    else
      redirect_to accounting_portal_access_index_path, alert: result.message
    end
  end

  def destroy
    PortalAdmin::RevokeGrant.call(grant: @grant, by: current_user)
    redirect_to accounting_portal_access_index_path, notice: "Access revoked."
  end

  def reset
    PortalAdmin::ResetAccess.call(person: @grant.portal_user, entity: ActsAsTenant.current_tenant, by: current_user)
    redirect_to accounting_portal_access_index_path, notice: "Second factor and password wiped; a new invitation was sent."
  end

  def verify_identity
    PortalAdmin::VerifyIdentity.call(person: @grant.portal_user, entity: ActsAsTenant.current_tenant, by: current_user)
    redirect_to accounting_portal_access_index_path, notice: "Identity recorded as verified."
  end

  def reinstate
    PortalAdmin::Reinstate.call(person: @grant.portal_user, entity: ActsAsTenant.current_tenant, by: current_user)
    redirect_to accounting_portal_access_index_path, notice: "Reinstated."
  end

  def branding
    brand = Portal::Branding.find_or_initialize_by(entity_id: current_entity_id)
    brand.assign_attributes(params.permit(:display_name, :primary_color, :background_color, :sender_name).to_h.compact_blank.merge(updated_by: current_user))
    if (upload = params[:logo]).respond_to?(:tempfile)
      brand.logo = upload.read
      brand.logo_content_type = upload.content_type
    end
    if brand.save
      Accounting::AuditLog.record!(auditable: brand, action: "portal_branding_changed", user: current_user, payload: brand.saved_changes.except("logo", "updated_at", "created_at").merge("logo_changed" => brand.saved_change_to_logo?))
      redirect_to accounting_portal_access_index_path, notice: "Look of the portal saved."
    else
      redirect_to accounting_portal_access_index_path, alert: brand.errors.full_messages.to_sentence
    end
  end

  private

  def current_entity_id = ActsAsTenant.current_tenant.id

  def find_grant
    @grant = Portal::Grant.where(entity_id: current_entity_id).find(params[:id])
  end
end

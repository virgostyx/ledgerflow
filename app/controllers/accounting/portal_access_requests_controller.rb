# B02a: the firm decides on a director's request that someone be given access: grant (an invitation goes out) or decline.
class Accounting::PortalAccessRequestsController < ApplicationController
  before_action -> { require_feature!(:b02a) }
  before_action -> { authorize Accounting::PortalAccessPolicy, "#{action_name}?".to_sym, policy_class: Accounting::PortalAccessPolicy }
  before_action :find_request

  def grant
    result = PortalAdmin::Invite.call(entity: ActsAsTenant.current_tenant, email: @ask.email, full_name: @ask.full_name, role: @ask.role, by: current_user)
    if result.success?
      decide!("granted")
      redirect_to accounting_portal_access_index_path, notice: "Invitation sent."
    else
      redirect_to accounting_portal_access_index_path, alert: result.message
    end
  end

  def decline
    decide!("declined")
    redirect_to accounting_portal_access_index_path, notice: "Request declined."
  end

  private

  def find_request
    @ask = Portal::AccessRequest.where(entity_id: ActsAsTenant.current_tenant.id).find_by!(token: params[:token])
    redirect_to accounting_portal_access_index_path, alert: "That request was already decided." unless @ask.pending?
  end

  def decide!(status)
    @ask.update!(status: status, decided_by: current_user, decided_at: Time.current)
    Accounting::AuditLog.record!(auditable: @ask, action: "portal_access_request_#{status}", user: current_user, payload: { email: @ask.email, role: @ask.role })
  end
end

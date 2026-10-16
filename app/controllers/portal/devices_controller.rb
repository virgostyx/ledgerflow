class Portal::DevicesController < Portal::BaseController
  def index
    @devices = current_portal_user.devices.active.order(last_seen_at: :desc)
    @current_device = current_portal_session.device
  end

  def destroy
    device = current_portal_user.devices.active.find_by(token: params[:token])
    return not_in_scope(params[:token]) unless device

    device.revoke!
    record_event("device_revoked", target_token: device.token)
    redirect_to devices_path, notice: "Device signed out."
  end
end

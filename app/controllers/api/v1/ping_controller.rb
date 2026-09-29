# Connection check (health_check of a third-party adapter): confirms the key, the entity and the granted scopes.
class Api::V1::PingController < Api::V1::BaseController
  self.action_scopes = { show: :any }

  def show
    render json: { status: "ok", entity: ActsAsTenant.current_tenant&.name, api_client: @api_client&.name,
                   scopes: @api_client&.scopes, time: Time.current.iso8601 }
  end
end

# Two ways in:
# - API key ("lf_..."): an ApiClient fixes the entity and limits what the caller may do (action_scopes).
#   An action without a declared scope is refused (fail closed). Every call is logged in api_requests.
# - Legacy JWT (deprecated): entity from the payload, full access, not logged.
class Api::V1::BaseController < ActionController::API
  class_attribute :action_scopes, default: {}

  around_action :authenticate_and_log

  private

  def authenticate_and_log
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    token   = request.headers["Authorization"]&.split(" ")&.last
    token.to_s.start_with?("lf_") ? run_as_client(token) { yield } : run_as_jwt(token) { yield }
  ensure
    log_request(started) if @api_client
  end

  def run_as_client(token)
    @api_client = ApiClient.authenticate(token)
    return render(json: { error: "Unauthorized" }, status: :unauthorized) unless @api_client

    ActsAsTenant.current_tenant = @api_client.entity
    scope = action_scopes[action_name.to_sym]
    return render(json: { error: "Forbidden", required_scope: scope }, status: :forbidden) unless scope && @api_client.allows?(scope)

    yield
  end

  def run_as_jwt(token)
    payload = Api::JwtService.decode(token)
    ActsAsTenant.current_tenant = Entity.find_by(id: payload["entity_id"])
    yield
  rescue Api::AuthenticationError
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def log_request(started)
    @api_client.update_columns(last_used_at: Time.current)
    @api_client.api_requests.create!(
      http_method: request.method, path: request.path, status: response.status,
      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
      external_ref: params[:external_ref]
    )
  end
end

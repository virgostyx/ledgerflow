# Two ways in:
# - API key ("lf_..."): an ApiClient fixes the entity and limits what the caller may do (action_scopes).
#   An action without a declared scope is refused (fail closed); `:any` means any active client. Every call is logged in api_requests.
# - Legacy JWT (deprecated, closed unless LEGACY_JWT_ENABLED=1): entity from the payload, no owner and no scope of its own;
#   only the routes that declare a scope are served, and each call is recorded in the entity's audit trail.
class Api::V1::BaseController < ActionController::API
  NOT_ENABLED = { error: "The BudgetFlow integration is not enabled for this entity" }.freeze

  class_attribute :action_scopes, default: {}
  # :budgetflow (the integration, closed to entities that did not declare it) or :public (the public API of F13c, open to entities that turned it on)
  class_attribute :surface, default: :budgetflow

  around_action :authenticate_and_log

  private

  def authenticate_and_log
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    set_audit_context
    token   = request.headers["Authorization"]&.split(" ")&.last
    token.to_s.start_with?("lf_") ? run_as_client(token) { yield } : run_as_jwt(token) { yield }
  ensure
    log_request(started) if @api_client
    log_legacy_request if @legacy_entity
  end

  # Request context read by the audit trail (R18); the API client, when there is one, is added by run_as_client.
  def set_audit_context
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent.to_s.first(255)
    Current.request_id = request.request_id
  end

  def run_as_client(token)
    @api_client = ApiClient.authenticate(token)
    return deny(:unauthorized, "Unauthorized") unless @api_client

    ActsAsTenant.current_tenant = @api_client.entity
    Current.api_client = @api_client
    return deny(:forbidden, NOT_ENABLED[:error]) unless surface_enabled?(@api_client.entity)

    scope = action_scopes[action_name.to_sym]
    return deny(:forbidden, "Forbidden", required_scope: scope) unless scope == :any || (scope && @api_client.allows?(scope))

    yield
  end

  def surface_enabled?(entity) = surface == :public ? entity.feature?(:f13) : entity.budgetflow?

  # Every refusal of the authentication goes through here: the public API answers in problem+json (Api::V1::Public::BaseController).
  def deny(status, error, **extra) = render(json: { error: error }.merge(extra), status: status)

  def run_as_jwt(token)
    return deny(:unauthorized, "Unauthorized") unless Rails.configuration.x.legacy_jwt_enabled && surface == :budgetflow

    payload = Api::JwtService.decode(token)
    ActsAsTenant.current_tenant = Entity.find_by(id: payload["entity_id"])
    return deny(:forbidden, NOT_ENABLED[:error]) unless ActsAsTenant.current_tenant&.budgetflow?

    @legacy_entity = ActsAsTenant.current_tenant
    # fail closed, like a key: a route that declares no scope is not served
    return render(json: { error: "Forbidden" }, status: :forbidden) unless action_scopes[action_name.to_sym]

    yield
  rescue Api::AuthenticationError
    deny(:unauthorized, "Unauthorized")
  end

  # The JWT has no api_requests row (no client): the entity's audit trail keeps the trace instead.
  def log_legacy_request
    Accounting::AuditLog.record!(auditable: @legacy_entity, action: "api_legacy_jwt",
                                 payload: { http_method: request.method, path: request.path, status: response.status, ip: request.remote_ip })
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

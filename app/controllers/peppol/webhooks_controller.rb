# Public endpoint called by an entity's Access Point. The token in the URL designates the entity (and so which
# adapter and which secret check the signature); the adapter turns the call into normalized events.
class Peppol::WebhooksController < ApplicationController
  skip_before_action :authenticate_user!
  skip_forgery_protection

  def receive
    entity = ActsAsTenant.without_tenant { Entity.find_by(peppol_webhook_token: request.path_parameters[:token]) }
    return head :not_found unless entity&.peppol_access_point

    events = Peppol::AccessPoint.for(entity).parse_webhook(headers: request.headers, body: request.body.read)
    events.each do |event|
      result = Peppol::HandleEvent.call(event: event)
      Rails.logger.warn("[Peppol] #{event.kind} event not applied: #{result.message}") if result.failure?
    end
    head :ok
  rescue Peppol::AccessPoint::InvalidSignature => e
    log_rejection(entity, e)
    head :unauthorized
  rescue Peppol::AccessPoint::Error
    head :bad_request
  end

  private

  # A call that does not pass the signature is refused and kept in the audit trail of the entity (who called, why it was refused).
  def log_rejection(entity, error)
    ActsAsTenant.with_tenant(entity) do
      Accounting::AuditLog.record!(auditable: entity, action: "peppol_webhook_rejected", user: nil, ip_address: request.remote_ip, payload: { reason: error.message })
    end
  end
end

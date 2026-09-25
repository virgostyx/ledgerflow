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
  rescue Peppol::AccessPoint::InvalidSignature
    head :unauthorized
  rescue Peppol::AccessPoint::Error
    head :bad_request
  end
end

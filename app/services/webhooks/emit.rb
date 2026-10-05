# F13c: an event of the application, for every subscription of the entity that asked for it. A delivery row is written in the transaction of what
# happened (so there is no delivery of a thing that was rolled back), and the sending is queued once everything is committed.
# `data` holds the identifiers and the summary, never more than a receiver needs: it can read the rest through the API.
class Webhooks::Emit
  PAYLOAD_VERSION = 1

  # `data` may be a lambda: it is only called, inside the tenant of the entity, when someone is subscribed (a model callback often runs after the tenant
  # of the request is gone, and most entities have no subscription at all).
  def self.call(event, data, entity: ActsAsTenant.current_tenant)
    return [] unless entity&.feature?(:f13)

    subscriptions = WebhookSubscription.unscoped.where(entity_id: entity.id).subscribed_to(event).to_a
    return [] if subscriptions.empty?

    data = ActsAsTenant.with_tenant(entity) { data.call } if data.respond_to?(:call)
    event_id = SecureRandom.uuid
    subscriptions.map do |subscription|
      delivery = WebhookDelivery.unscoped.create!(entity_id: entity.id, webhook_subscription: subscription, event: event, event_id: event_id, payload_version: PAYLOAD_VERSION,
                                                  payload: envelope(event, event_id, entity, data), next_attempt_at: Time.current)
      ActiveRecord.after_all_transactions_commit { Webhooks::DeliverJob.perform_later(delivery.id) }
      delivery
    end
  end

  def self.envelope(event, event_id, entity, data)
    { "id" => event_id, "event" => event, "payload_version" => PAYLOAD_VERSION, "created_at" => Time.current.utc.iso8601, "entity_id" => entity.id, "data" => data.as_json }
  end
  private_class_method :envelope
end

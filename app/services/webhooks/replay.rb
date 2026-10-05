# F13c: sends a delivery again, as a new delivery of the same event (same event id: the receiver can tell it is the same), after a failure, a suspension
# or on request. => the new delivery
class Webhooks::Replay
  def self.call(delivery)
    copy = WebhookDelivery.create!(webhook_subscription: delivery.webhook_subscription, event: delivery.event, event_id: delivery.event_id, payload_version: delivery.payload_version,
                                   payload: delivery.payload, replay_of: delivery, next_attempt_at: Time.current)
    ActiveRecord.after_all_transactions_commit { Webhooks::DeliverJob.perform_later(copy.id) }
    copy
  end
end

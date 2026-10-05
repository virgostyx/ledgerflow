# F13c: sends a delivery, and again later when it failed (see Webhooks::Deliver).
class Webhooks::DeliverJob < ApplicationJob
  queue_as :default

  def perform(delivery_id)
    delivery = WebhookDelivery.unscoped.find_by(id: delivery_id) or return
    ActsAsTenant.with_tenant(delivery.entity) { Webhooks::Deliver.call(delivery) }
  end
end

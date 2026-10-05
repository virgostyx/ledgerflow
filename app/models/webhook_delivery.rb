# F13c: one event sent, or to be sent, to one subscription, with what became of it.
class WebhookDelivery < ApplicationRecord
  STATUSES = %w[pending delivered failed held].freeze

  acts_as_tenant :entity

  belongs_to :webhook_subscription
  belongs_to :replay_of, class_name: "WebhookDelivery", optional: true

  validates :status, inclusion: { in: STATUSES }
end

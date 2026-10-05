# F13c: where an entity wants to be told of what happens, and what. The URL must be public (Webhooks::UrlGuard), the secret signs every delivery and
# can be rotated (the old one signs too for a day, so that the receiver can change over). Too many failures in a row suspend it.
class WebhookSubscription < ApplicationRecord
  EVENTS = %w[entry.posted entry.reversed reconciliation.created period.locked document.created peppol.received closing.completed].freeze
  ROTATION_GRACE = 24.hours

  acts_as_tenant :entity

  belongs_to :created_by, class_name: "User", optional: true
  has_many :deliveries, class_name: "WebhookDelivery", dependent: :destroy

  encrypts :secret, :previous_secret

  validates :name, :url, presence: true
  validates :max_failures, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validate :known_events, :public_url

  scope :subscribed_to, ->(event) { where(active: true, suspended_at: nil).where("? = ANY (events)", event) }

  def self.generate_secret = "whsec_#{SecureRandom.urlsafe_base64(32)}"

  def suspended? = suspended_at.present?

  # The secrets that sign a delivery: the current one, and the one before it for a day after a rotation.
  def signing_secrets
    [ secret, (previous_secret if secret_rotated_at && secret_rotated_at > ROTATION_GRACE.ago) ].compact
  end

  def rotate_secret!
    update!(previous_secret: secret, secret: self.class.generate_secret, secret_rotated_at: Time.current)
    secret
  end

  def suspend!(reason)
    update!(suspended_at: Time.current, suspended_reason: reason)
  end

  def resume!
    update!(suspended_at: nil, suspended_reason: nil, consecutive_failures: 0)
  end

  private

  def known_events
    unknown = events - EVENTS
    errors.add(:events, "unknown: #{unknown.join(', ')}") if unknown.any?
    errors.add(:events, "choose at least one") if events.empty?
  end

  def public_url
    Webhooks::UrlGuard.check_syntax(url) if url.present?
  rescue Webhooks::UrlGuard::Refused => e
    errors.add(:url, e.message)
  end
end

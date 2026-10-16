# A browser a person signed in from, known by a cookie of its own (stored as a digest).
class Portal::Device < ApplicationRecord
  belongs_to :portal_user

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(cookie) = Digest::SHA256.hexdigest(cookie.to_s)

  # [device, cookie value to set or nil, new?]. A cookie of a revoked or unknown device is a new device.
  def self.recognize(user, cookie, ip:, user_agent:)
    known = cookie.present? && user.devices.active.find_by(token_digest: digest(cookie))
    if known
      known.update_columns(last_seen_at: Time.current, ip_address: ip)
      return [ known, nil, false ]
    end

    value = SecureRandom.urlsafe_base64(32)
    now = Time.current
    first = !user.devices.exists?
    device = create!(portal_user: user, token: SecureRandom.urlsafe_base64(12), token_digest: digest(value), ip_address: ip, user_agent: user_agent.to_s.first(255), first_seen_at: now, last_seen_at: now)
    [ device, value, !first ]
  end

  def revoke!
    transaction do
      update!(revoked_at: Time.current)
      Portal::Session.where(device_id: id, revoked_at: nil).update_all(revoked_at: Time.current)
    end
  end

  def to_param = token
end

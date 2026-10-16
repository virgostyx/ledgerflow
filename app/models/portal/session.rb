# One sign-in of a person on one device. Only the digest of its token is kept; a revoked or suspended person loses it at the next request.
class Portal::Session < ApplicationRecord
  belongs_to :portal_user

  def self.start!(user, ip:, user_agent:)
    token = SecureRandom.urlsafe_base64(32)
    [ create!(portal_user: user, token_digest: digest(token), ip_address: ip, user_agent: user_agent.to_s[0, 255], last_seen_at: Time.current), token ]
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  # The live session of this token, touched; nil once idle for 30 minutes, 12 hours old, revoked, or its person is no longer active.
  def self.authenticate(token)
    return if token.blank?

    session = includes(:portal_user).find_by(token_digest: digest(token), revoked_at: nil)
    return unless session&.live?

    session.update_columns(last_seen_at: Time.current)
    session
  end

  def self.revoke_all!(user) = where(portal_user_id: user.id, revoked_at: nil).update_all(revoked_at: Time.current)

  def live?
    revoked_at.nil? && last_seen_at > Portal::IDLE_TIMEOUT.ago && created_at > Portal::SESSION_MAXIMUM.ago && (portal_user.active? || portal_user.invited?)
  end

  def revoke! = update!(revoked_at: Time.current)

  def passed_second_factor! = update!(second_factor_at: Time.current)

  def second_factor_recent? = second_factor_at.present? && second_factor_at > Portal::RECENT_SECOND_FACTOR.ago
end

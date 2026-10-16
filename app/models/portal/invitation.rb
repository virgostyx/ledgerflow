# The way in: a token sent to an address, valid seven days, used once, stored only as a digest. Accepting it writes the grant.
class Portal::Invitation < ApplicationRecord
  belongs_to :portal_user
  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  belongs_to :created_by, class_name: "User", optional: true

  validates :role, inclusion: { in: Portal::ROLES }
  validate :portal_is_on

  # Returns [invitation, token]; the token is not kept anywhere.
  def self.issue!(entity:, email:, full_name:, role:, by:, capabilities: nil)
    token = SecureRandom.urlsafe_base64(32)
    invitation = transaction do
      person = PortalUser.find_by_email(email) || PortalUser.create!(email: email, full_name: full_name, created_by: by, password: SecureRandom.base64(24))
      create!(portal_user: person, entity_id: entity.id, email: person.email, role: role, created_by: by, token_digest: digest(token),
              capabilities: capabilities || Portal::ROLE_CAPABILITIES.fetch(role.to_s, []), expires_at: Portal::INVITATION_VALIDITY.from_now)
    end
    [ invitation, token ]
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_usable(token)
    where(used_at: nil).where("expires_at > ?", Time.current).find_by(token_digest: digest(token))
  end

  def accept!
    transaction do
      update!(used_at: Time.current)
      Portal::Grant.create!(portal_user: portal_user, entity_id: entity_id, role: role, capabilities: capabilities, created_by: created_by)
    end
  end

  private

  def portal_is_on
    errors.add(:base, "the client portal is not on for this company") unless company&.portal_enabled
  end
end

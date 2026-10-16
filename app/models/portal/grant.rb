# What a person from outside may do in one company. A right exists only if `capabilities` lists it.
class Portal::Grant < ApplicationRecord
  belongs_to :portal_user
  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  validates :role, inclusion: { in: Portal::ROLES }

  scope :in_force, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def allows?(capability) = capabilities.include?(capability.to_s)
end

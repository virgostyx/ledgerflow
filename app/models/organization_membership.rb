# F12a: a person in an organization: an owner manages it (its entities and its people), a member sees it.
class OrganizationMembership < ApplicationRecord
  ROLES = %w[owner member].freeze

  belongs_to :organization
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }
  validate :keep_an_owner, on: :update

  before_destroy :keep_an_owner_before_destroy, unless: -> { destroyed_by_association }

  private

  def keep_an_owner
    return unless role_was == "owner" && role != "owner"

    errors.add(:role, "an organization keeps at least one owner") unless self.class.where(organization_id: organization_id, role: "owner").where.not(id: id).exists?
  end

  def keep_an_owner_before_destroy
    return unless role == "owner" && !self.class.where(organization_id: organization_id, role: "owner").where.not(id: id).exists?

    errors.add(:base, "an organization keeps at least one owner")
    throw :abort
  end
end

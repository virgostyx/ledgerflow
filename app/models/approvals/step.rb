# One level of a policy: who may decide, and whether one of them is enough or all are needed.
class Approvals::Step < ApplicationRecord
  self.table_name = "approval_steps"

  # The roles a step may name are the ones the matrix lets approve.
  APPROVER_ROLES = UserEntity.roles.keys.select { |role| Permissions.allowed?(role, "approvals.approve") }.freeze

  enum :mode, { any_of: 0, all_of: 1 }

  belongs_to :policy, class_name: "Approvals::Policy", inverse_of: :steps
  belongs_to :escalate_to, class_name: "User", optional: true

  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :policy_id }
  validate :someone_can_approve
  validate :roles_can_approve

  private

  def someone_can_approve
    errors.add(:base, "needs at least one approver") if approver_user_ids.blank? && approver_roles.blank?
  end

  def roles_can_approve
    unknown = approver_roles - APPROVER_ROLES
    errors.add(:approver_roles, "cannot approve: #{unknown.join(', ')}") if unknown.any?
  end
end

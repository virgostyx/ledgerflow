# Someone stands in for an approver for a while (B01a). Not transitive, limited in time, and it never lets anyone approve their own entries.
class Approvals::Delegation < ApplicationRecord
  self.table_name = "approval_delegations"

  include Accounting::AuditTrailed # who stands in for whom, from when to when, is part of the record

  acts_as_tenant :entity

  belongs_to :delegator, class_name: "User"
  belongs_to :delegate, class_name: "User"

  validates :starts_on, :ends_on, :reason, presence: true
  validate :ends_after_start
  validate :not_to_oneself
  validate :both_can_approve, on: :create

  scope :in_force_on, ->(date) { where("starts_on <= :d AND ends_on >= :d", d: date) }

  private

  def both_can_approve
    { delegator: delegator_id, delegate: delegate_id }.each do |role, user_id|
      allowed = UserEntity.current.where(user_id: user_id, entity_id: entity_id).includes(:custom_role).any? { |membership| membership.allows?("approvals.approve") }
      errors.add(role, "cannot approve in this entity") unless allowed
    end
  end

  def ends_after_start
    errors.add(:ends_on, "must not be before the start") if starts_on && ends_on && ends_on < starts_on
  end

  def not_to_oneself
    errors.add(:delegate, "cannot be the delegator") if delegator_id && delegator_id == delegate_id
  end
end

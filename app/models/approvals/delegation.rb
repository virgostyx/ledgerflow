# Someone stands in for an approver for a while (B01a). Not transitive, limited in time, and it never lets anyone approve their own entries.
class Approvals::Delegation < ApplicationRecord
  self.table_name = "approval_delegations"

  acts_as_tenant :entity

  belongs_to :delegator, class_name: "User"
  belongs_to :delegate, class_name: "User"

  validates :starts_on, :ends_on, :reason, presence: true
  validate :ends_after_start
  validate :not_to_oneself

  scope :in_force_on, ->(date) { where("starts_on <= :d AND ends_on >= :d", d: date) }

  private

  def ends_after_start
    errors.add(:ends_on, "must not be before the start") if starts_on && ends_on && ends_on < starts_on
  end

  def not_to_oneself
    errors.add(:delegate, "cannot be the delegator") if delegator_id && delegator_id == delegate_id
  end
end

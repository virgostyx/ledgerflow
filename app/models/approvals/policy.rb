# A rule that says who must approve what (B01a). The first active policy that matches, by priority, applies to a subject;
# a request keeps the version it was created under, so editing a policy never moves what is in progress.
class Approvals::Policy < ApplicationRecord
  self.table_name = "approval_policies"

  include Accounting::AuditTrailed # every edit of a policy is in the audit trail, field by field

  acts_as_tenant :entity

  enum :subject, { purchase_invoice: 0, payment_batch: 1 }

  has_many :requests, class_name: "Approvals::Request", foreign_key: :policy_id, inverse_of: :policy, dependent: :nullify
  has_many :steps, -> { order(:position) }, class_name: "Approvals::Step", foreign_key: :policy_id, inverse_of: :policy, dependent: :destroy

  validates :name, presence: true
  validates :subject, presence: true
  validates :priority, numericality: { only_integer: true }

  scope :active, -> { where(active: true) }
  scope :by_priority, -> { order(:priority, :id) }
end

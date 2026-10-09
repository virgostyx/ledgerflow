# What one approver decided at one step, from which channel, on which content.
class Approvals::Decision < ApplicationRecord
  self.table_name = "approval_decisions"

  acts_as_tenant :entity

  enum :decision, { approved: 0, rejected: 1, changes_requested: 2, transferred: 3 }
  enum :channel, { web: 0, mobile: 1, api: 2 }

  belongs_to :request, class_name: "Approvals::Request", inverse_of: :decisions
  belongs_to :approver, class_name: "User"
  belongs_to :on_behalf_of, class_name: "User", optional: true

  before_validation { self.decided_at ||= Time.current }

  validates :step_position, numericality: { only_integer: true, greater_than: 0 }
  validates :content_fingerprint, format: { with: /\A\h{64}\z/ }
  validates :comment, presence: true, if: -> { rejected? || changes_requested? }
end

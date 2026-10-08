# What the agent proposes (A07): an entry to draft or a task to create, validated by the server and stored (encrypted) until the author of the conversation decides. Nothing here writes to the books;
# the controller does, on a click, with the rights of the person. A proposal that nobody decided within seven days expires, and one whose conversation is deleted is cancelled.
class Agent::Proposal < ApplicationRecord
  self.table_name = "agent_proposals"

  KINDS = %w[entry_draft task note].freeze
  LIFETIME = 7.days
  MAX_PER_ANSWER = 20

  acts_as_tenant :entity

  belongs_to :user
  belongs_to :conversation, class_name: "Agent::Conversation", optional: true
  belongs_to :message, class_name: "Agent::Message", optional: true

  encrypts :payload
  encrypts :reject_reason

  enum :status, { pending: "pending", created: "created", rejected: "rejected", expired: "expired", cancelled: "cancelled" }, default: "pending"

  validates :kind, inclusion: { in: KINDS }
  validates :payload, :expires_at, presence: true

  before_validation { self.expires_at ||= LIFETIME.from_now }

  scope :live, -> { pending.where("expires_at > ?", Time.current) }

  # Marks as expired the proposals nobody decided in time (run by the retention job, and checked again at every click).
  def self.expire_due! = pending.where(expires_at: ..Time.current).update_all(status: "expired", updated_at: Time.current)

  def data = @data ||= JSON.parse(payload)
  # Waiting but too late (the status turns to expired the next time the due ones are swept).
  def lapsed? = pending? && expires_at <= Time.current
  def decidable_by?(person) = pending? && !lapsed? && person.id == user_id
  def total = BigDecimal(data.fetch("totals", {}).fetch("debit", "0"))

  def reject!(reason)
    update!(status: "rejected", outcome: "rejected", reject_reason: reason.to_s.strip.first(300).presence, decided_at: Time.current)
  end

  def created!(record, outcome:, changed: [])
    update!(status: "created", outcome: outcome, changed_fields: changed, result_type: record.class.name, result_id: record.id, decided_at: Time.current)
  end
end

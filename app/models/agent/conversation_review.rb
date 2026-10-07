# One reading of someone else's conversation by an owner (A01): the exceptional procedure leaves this record, a line in the audit trail and a notice to the author. The reading
# itself is open for a short while only; reading again is another procedure.
class Agent::ConversationReview < ApplicationRecord
  self.table_name = "agent_conversation_reviews"

  OPEN_FOR = 30.minutes
  MIN_REASON = 10

  acts_as_tenant :entity

  belongs_to :conversation, class_name: "Agent::Conversation", optional: true # gone when the conversation is deleted; the record stays
  belongs_to :author, class_name: "User"
  belongs_to :reviewer, class_name: "User"

  encrypts :reason

  validates :reason, length: { minimum: MIN_REASON, message: "must say why (at least #{MIN_REASON} characters)" }

  def open? = conversation.present? && reviewed_at > OPEN_FOR.ago
end

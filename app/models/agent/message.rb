# One turn of a conversation (A01). The content is encrypted: a conversation holds figures and names of the entity.
class Agent::Message < ApplicationRecord
  self.table_name = "agent_messages"

  belongs_to :conversation, class_name: "Agent::Conversation", inverse_of: :messages
  has_many :proposals, class_name: "Agent::Proposal", foreign_key: :message_id, inverse_of: :message, dependent: :nullify
  has_many :feedbacks, class_name: "Agent::Feedback", dependent: :destroy
  has_many :tool_calls, class_name: "Agent::ToolCall", dependent: :destroy

  encrypts :content, :sent_payload

  enum :role,   { user: "user", assistant: "assistant", tool: "tool" }, validate: false
  enum :status, { complete: "complete", stopped: "stopped", failed: "failed" }, default: "complete"

  validates :role, presence: true
end

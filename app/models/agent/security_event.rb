# Something the agent's defences noticed (A03): visible to the owners, and written in the audit trail. The excerpt is short, masked and encrypted.
class Agent::SecurityEvent < ApplicationRecord
  self.table_name = "agent_security_events"

  KINDS = %w[forbidden_argument forbidden_tool repeated_forbidden unknown_tool suspicious_content secret_removed url_removed invalid_citation limit_reached].freeze

  acts_as_tenant :entity

  belongs_to :conversation, class_name: "Agent::Conversation", optional: true
  belongs_to :user, optional: true

  encrypts :excerpt

  validates :kind, inclusion: { in: KINDS }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
end

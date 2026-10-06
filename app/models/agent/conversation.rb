# A talk between one person and the AI agent, about one entity (A01). Only its author sees it; changing entity opens another. It holds
# a reference to the object the panel was opened on, never text copied from the screen.
class Agent::Conversation < ApplicationRecord
  self.table_name = "agent_conversations"

  acts_as_tenant :entity

  belongs_to :user
  has_many :messages, class_name: "Agent::Message", foreign_key: :conversation_id, inverse_of: :conversation, dependent: :destroy

  enum :status, { active: "active", archived: "archived" }, default: "active"

  scope :visible_to, ->(user) { where(user: user) }

  def archive! = update!(status: :archived, archived_at: Time.current)
end

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

  # The Stop button writes the time; the runner looks at it between two steps. A new question starts with a clean slate.
  def request_stop! = update_columns(stop_requested_at: Time.current)
  def clear_stop!   = update_columns(stop_requested_at: nil)
  def stop_requested? = self.class.where(id: id).where.not(stop_requested_at: nil).exists?
end

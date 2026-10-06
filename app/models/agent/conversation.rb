# A talk between one person and the AI agent, about one entity (A01). Only its author sees it; changing entity opens another. It holds
# a reference to the object the panel was opened on, never text copied from the screen.
class Agent::Conversation < ApplicationRecord
  self.table_name = "agent_conversations"

  acts_as_tenant :entity

  encrypts :title # the first words of the first question: it can hold a name

  belongs_to :user
  has_many :pseudonyms, class_name: "Agent::Pseudonym", foreign_key: :conversation_id, inverse_of: :conversation, dependent: :delete_all
  has_many :messages, class_name: "Agent::Message", foreign_key: :conversation_id, inverse_of: :conversation, dependent: :destroy

  enum :status, { active: "active", archived: "archived" }, default: "active"

  # What was said goes with the conversation; of its security events only the metadata stays (the excerpt could hold what was said).
  before_destroy { Agent::SecurityEvent.where(conversation_id: id).update_all(excerpt: nil) }

  scope :visible_to, ->(user) { where(user: user) }

  # The tokens of this conversation, loaded once: the redactor writes them, the display reads them.
  def pseudonym_table = @pseudonym_table ||= Agent::Pseudonyms.new(self)

  def reveal(text) = pseudonym_table.reveal(text)

  def archive! = update!(status: :archived, archived_at: Time.current)

  # The Stop button writes the time; the runner looks at it between two steps. A new question starts with a clean slate.
  def request_stop! = update_columns(stop_requested_at: Time.current)
  def clear_stop!   = update_columns(stop_requested_at: nil)
  def start_answering! = update_columns(answering_since: Time.current)
  def done_answering!  = update_columns(answering_since: nil)
  def stop_requested? = self.class.where(id: id).where.not(stop_requested_at: nil).exists?
end

# One call of the model to a tool, on the answer it served (A02). The arguments are encrypted; the result is not kept, only how big it was and whether it was partial.
class Agent::ToolCall < ApplicationRecord
  self.table_name = "agent_tool_calls"

  belongs_to :message, class_name: "Agent::Message"

  encrypts :arguments

  enum :status, { ok: "ok", error: "error" }, validate: false

  validates :tool, :status, presence: true
end

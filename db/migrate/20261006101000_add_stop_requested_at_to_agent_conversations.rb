# A01: the "Stop" button. The request writes the time here; the runner reads it between two steps, so that nothing runs after the stop. Reversible.
class AddStopRequestedAtToAgentConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_conversations, :stop_requested_at, :datetime
  end
end

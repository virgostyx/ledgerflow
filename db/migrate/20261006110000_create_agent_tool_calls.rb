# A02: what the agent asked of each tool, so that an answer can be replayed and audited. The arguments are encrypted (they may hold a name or a reference); the result
# is kept as a summary only, never in full. Reversible.
class CreateAgentToolCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_tool_calls do |t|
      t.references :message, null: false, foreign_key: { to_table: :agent_messages }
      t.string  :tool, null: false
      t.text    :arguments                              # encrypted JSON
      t.string  :status, null: false                    # ok | error
      t.string  :error                                  # forbidden, not_found, invalid_arguments, timeout, too_large, internal_error
      t.integer :row_count
      t.boolean :truncated, null: false, default: false
      t.integer :duration_ms
      t.timestamps
    end
  end
end

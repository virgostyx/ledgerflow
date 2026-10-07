# A05: what an answer rests on. The sources it cites (numbered, in order of appearance), the state of the books it was computed from (`ledger_version`), and, for each tool call, a fingerprint of the
# result and the amounts it gave: that is what "Check" replays to say whether the answer is still valid. Reversible.
class AddAgentCitations < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_messages, :citations, :jsonb, null: false, default: []
    add_column :agent_messages, :ledger_version, :string
    add_column :agent_tool_calls, :result_digest, :string
    add_column :agent_tool_calls, :result_amounts, :jsonb, null: false, default: []
  end
end

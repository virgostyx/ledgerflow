# A03: what the agent's defences noticed, for the owners and for the audit trail: an argument it is not allowed to give, a tool refused again and again, content that looks
# like an instruction to an AI, a secret or a link removed from an answer. The excerpt is encrypted and masked. `flags` on a message are what showed up in it (a badge). Reversible.
class CreateAgentSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_security_events do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :conversation, foreign_key: { to_table: :agent_conversations, on_delete: :nullify }
      t.references :user, foreign_key: true
      t.string :kind, null: false
      t.string :tool
      t.text   :excerpt                                    # encrypted, masked, short
      t.timestamps
    end
    add_index :agent_security_events, %i[entity_id created_at]
    add_index :agent_security_events, %i[conversation_id kind]

    add_column :agent_messages, :flags, :jsonb, null: false, default: []
  end
end

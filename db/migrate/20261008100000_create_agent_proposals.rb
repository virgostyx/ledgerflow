# A07: what the agent proposes and a person decides. A proposal (an entry to draft, a task to create) is validated by the server, stored here (encrypted) and waits for a click of the conversation's author;
# nothing reaches the books before. The outcome (accepted as it was, modified, rejected) is kept to measure the proposals, never to change a setting. `agent_settings.review_threshold` is the amount
# above which the card asks to read the justification before the draft can be created. Reversible.
class CreateAgentProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_proposals do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true                       # the author of the conversation, the only one who may decide
      t.references :conversation, foreign_key: { to_table: :agent_conversations, on_delete: :nullify }
      t.references :message, foreign_key: { to_table: :agent_messages, on_delete: :nullify }
      t.string   :kind, null: false                                            # entry_draft | task
      t.string   :status, null: false, default: "pending"                      # pending | created | rejected | expired | cancelled
      t.text     :payload, null: false                                         # encrypted: the validated proposal as JSON
      t.boolean  :warnings_present, null: false, default: false
      t.boolean  :review_required, null: false, default: false
      t.string   :outcome                                                      # accepted_as_is | modified | rejected
      t.jsonb    :changed_fields, null: false, default: []
      t.text     :reject_reason                                                # encrypted
      t.bigint   :result_id                                                    # the draft entry or the task that was created
      t.string   :result_type
      t.datetime :expires_at, null: false
      t.datetime :decided_at
      t.timestamps
    end
    add_index :agent_proposals, %i[entity_id status]
    add_column :agent_settings, :review_threshold, :decimal, precision: 15, scale: 2, null: false, default: 5000
  end
end

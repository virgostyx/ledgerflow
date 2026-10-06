# A01: the conversations of the AI agent and what is said in them. A conversation belongs to one entity and is visible to its author only; its content (messages, comments) is
# encrypted by the models. Settings are one row per entity: the agent is off until an owner turns it on (and, from A04, accepts the consent). Reversible.
class CreateAgentFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_conversations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user,   null: false, foreign_key: true
      t.string  :title
      t.string  :origin_screen
      t.jsonb   :context_ref, null: false, default: {}   # the object the panel was opened on: { type:, id: }, never copied text
      t.string  :status, null: false, default: "active"
      t.datetime :archived_at
      t.timestamps
    end
    add_index :agent_conversations, %i[entity_id user_id updated_at]

    create_table :agent_messages do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.string  :role, null: false
      t.text    :content                              # encrypted JSON
      t.string  :status, null: false, default: "complete"
      t.string  :model
      t.string  :manifest_hash
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :latency_ms
      t.timestamps
    end

    create_table :agent_feedback do |t|
      t.references :message, null: false, foreign_key: { to_table: :agent_messages }
      t.references :user,    null: false, foreign_key: true
      t.string :rating, null: false
      t.string :category
      t.text   :comment                               # encrypted
      t.timestamps
    end
    add_index :agent_feedback, %i[message_id user_id], unique: true

    create_table :agent_settings do |t|
      t.references :entity, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.integer :retention_days, null: false, default: 90
      t.timestamps
    end
  end
end

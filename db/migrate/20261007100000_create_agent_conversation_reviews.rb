# A01: an owner who reads someone else's conversation does it by an exceptional procedure: a reason, a second factor, a line in the audit trail and a notice to the author. This is the
# record of each reading (who, which conversation, why, when). It outlives the conversation, whose content is deleted with it. Reversible.
class CreateAgentConversationReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_conversation_reviews do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :conversation, foreign_key: { to_table: :agent_conversations, on_delete: :nullify }
      t.references :author,   null: false, foreign_key: { to_table: :users }
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.text     :reason, null: false                      # encrypted
      t.integer  :message_count, null: false, default: 0
      t.datetime :reviewed_at, null: false
      t.timestamps
    end
  end
end

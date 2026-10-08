# A11: the texts the agent drafts (reminders, requests for documents, comments on a variation, summaries, replies, rewrites): kept encrypted with their versions and the facts they use, until a person uses, edits or
# rejects them. The agent has no way to send: a draft goes out only through the screens that already exist, by a person. `agent_settings.writing_profile` is the style of the company, set by an owner;
# `dunning_items.agent_draft_id` marks a reminder whose text the agent wrote, so that no automatic sending ever takes it. Reversible.
class CreateAgentTextDrafts < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_settings, :writing_profile, :jsonb, null: false, default: {}
    add_column :dunning_items, :agent_draft_id, :bigint
    add_index :dunning_items, :agent_draft_id, where: "agent_draft_id IS NOT NULL"

    create_table :agent_text_drafts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :conversation, foreign_key: { to_table: :agent_conversations, on_delete: :nullify }
      t.references :message, foreign_key: { to_table: :agent_messages, on_delete: :nullify }
      t.references :partner, foreign_key: { to_table: :accounting_partners, on_delete: :nullify }
      t.string  :kind, null: false                                  # dunning_letter | client_request | variation_comment | summary | reply_email | rewrite
      t.string  :language, null: false, default: "en"
      t.integer :level                                              # the reminder level, for a dunning letter
      t.text    :payload, null: false                               # encrypted: { versions: [{ subject:, body:, instruction:, at: }], facts: [...], warnings: [...] }
      t.string  :status, null: false, default: "draft"              # draft | used | rejected
      t.string  :outcome                                            # used_as_is | modified | rejected
      t.integer :edit_distance                                      # between the text proposed and the text used
      t.string  :used_in                                            # reminder | task | comment | copied
      t.timestamps
    end
    add_index :agent_text_drafts, %i[entity_id status]
  end
end

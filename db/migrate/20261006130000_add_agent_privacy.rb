# A04: what may go to the language model, entity by entity and class of data by class of data; the owner's consent, by version of its text; the pseudonyms of a conversation
# (reversible, encrypted); and, on a partner, whether it is a natural person (nullable: unknown is treated as a person, the prudent reading). Reversible.
class AddAgentPrivacy < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_settings, :data_class_modes, :jsonb, null: false, default: {}
    add_column :agent_settings, :restricted, :boolean, null: false, default: false

    create_table :agent_consents do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :version, null: false
      t.references :accepted_by, null: false, foreign_key: { to_table: :users }
      t.datetime :accepted_at, null: false
      t.timestamps
    end
    add_index :agent_consents, %i[entity_id version], unique: true

    create_table :agent_pseudonyms do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.string :token, null: false
      t.string :kind, null: false                          # person | tax_identifier
      t.text   :real_value, null: false                    # encrypted (deterministic, so that a person can be found)
      t.timestamps
    end
    add_index :agent_pseudonyms, %i[conversation_id token], unique: true
    add_index :agent_pseudonyms, %i[conversation_id real_value], unique: true

    add_column :agent_messages, :redaction_stats, :jsonb, null: false, default: {}
    add_column :agent_messages, :sent_payload, :text                                         # encrypted: what was sent after masking, for "see what was sent"

    add_column :accounting_partners, :is_natural_person, :boolean
  end
end

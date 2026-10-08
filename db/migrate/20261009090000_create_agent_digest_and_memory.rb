# A10: the morning summary (what deserves attention, built from the read tools without the model, per person and per entity, kept encrypted) and the case memory (notes a person writes or confirms,
# read by the agent, never created by it). `agent_settings.digest_email_details` lets the entity put figures and names in the e-mail, which carries only counts and links by default. Reversible.
class CreateAgentDigestAndMemory < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_settings, :digest_email_details, :boolean, null: false, default: false

    create_table :agent_digest_preferences do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: false
      t.string  :frequency, null: false, default: "daily"           # daily | weekly
      t.integer :weekday, null: false, default: 1                    # 0 (Sunday) to 6, for weekly
      t.integer :send_hour, null: false, default: 8
      t.string  :time_zone, null: false, default: "Europe/Brussels"
      t.jsonb   :sections, null: false, default: []                  # empty: all the sections the person may see
      t.boolean :email, null: false, default: false
      t.datetime :last_built_at
      t.timestamps
    end
    add_index :agent_digest_preferences, %i[entity_id user_id], unique: true

    create_table :agent_digests do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string  :kind, null: false                                   # scheduled | event
      t.string  :event_type                                          # for an event: blocking_anomaly, cash_below_threshold, vat_due, period_with_drafts
      t.date    :local_date, null: false                             # the day of the person, to count one event per type and per day
      t.text    :payload, null: false                                # encrypted: { sections:, fingerprints: }
      t.integer :item_count, null: false, default: 0
      t.datetime :read_at
      t.timestamps
    end
    add_index :agent_digests, %i[user_id entity_id event_type local_date], unique: true, where: "kind = 'event'", name: "index_agent_digests_one_event_per_day"
    add_index :agent_digests, %i[entity_id user_id created_at]

    create_table :agent_memory_notes do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :scope_kind, null: false, default: "entity"          # entity | partner | account
      t.bigint  :scope_id
      t.text    :text, null: false                                   # encrypted, 500 characters at most
      t.string  :category, null: false, default: "other"             # convention | partner | deadline | reminder | other
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.string  :source, null: false, default: "manual"              # manual | proposal
      t.bigint  :proposal_id
      t.string  :status, null: false, default: "active"              # active | archived
      t.date    :valid_until
      t.datetime :confirmed_at
      t.datetime :last_used_at
      t.integer :uses_count, null: false, default: 0
      t.timestamps
    end
    add_index :agent_memory_notes, %i[entity_id status scope_kind scope_id]
  end
end

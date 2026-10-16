# B02c: the client's dashboard. A snapshot is figures the firm's side computed from the books (a whitelist of indicators, no name of a third party), fingerprinted, and kept: the client reads
# snapshots, never triggers a calculation. The firm may require its own approval before a snapshot is shown, writes "the accountant's word" (a human text, approved before it is shown), and sets
# alert rules (the forecast cash under a threshold).
class CreatePortalDashboards < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :snapshot_approval_required, :boolean, null: false, default: false

    create_table :portal_snapshots do |t|
      t.references :entity, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.jsonb :indicators, null: false, default: {}
      t.jsonb :series, null: false, default: {}
      t.boolean :provisional, null: false, default: true
      t.datetime :generated_at, null: false
      t.datetime :known_at, null: false
      t.string :sha256, null: false
      t.string :status, null: false, default: "published" # pending_review while the firm has to approve it
      t.datetime :published_at
      t.bigint :published_by_id
      t.text :accountant_word
      t.string :word_source # "human" or "agent_draft"
      t.datetime :word_approved_at
      t.bigint :word_approved_by_id
      t.timestamps
    end
    add_index :portal_snapshots, %i[entity_id status generated_at]

    create_table :portal_alert_rules do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :kind, null: false # "cash_below"
      t.decimal :threshold, precision: 15, scale: 2, null: false
      t.boolean :active, null: false, default: true
      t.date :last_alerted_on
      t.timestamps
    end
  end
end

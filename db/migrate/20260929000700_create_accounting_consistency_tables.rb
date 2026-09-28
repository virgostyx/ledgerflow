# R19 (docs/dev/reports/spec.md §13): consistency runs, their findings, and acknowledgements that
# outlive runs (keyed by the stable fingerprint of an anomaly).
class CreateAccountingConsistencyTables < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_consistency_runs do |t|
      t.bigint   :entity_id, null: false
      t.string   :trigger, null: false, default: "manual"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer  :duration_ms
      t.jsonb    :counts, null: false, default: {}
      t.jsonb    :errors_by_check, null: false, default: {}
      t.timestamps
    end
    add_index :accounting_consistency_runs, [ :entity_id, :started_at ]

    create_table :accounting_consistency_findings do |t|
      t.bigint :entity_id, null: false
      t.bigint :run_id, null: false
      t.string :check_id, null: false
      t.string :severity, null: false
      t.string :fingerprint, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.text   :message, null: false
      t.jsonb  :data, null: false, default: {}
      t.timestamps
    end
    add_index :accounting_consistency_findings, :run_id
    add_index :accounting_consistency_findings, [ :entity_id, :fingerprint ]

    create_table :accounting_consistency_acknowledgements do |t|
      t.bigint   :entity_id, null: false
      t.string   :fingerprint, null: false
      t.text     :comment, null: false
      t.bigint   :user_id
      t.datetime :acknowledged_at, null: false
      t.timestamps
    end
    add_index :accounting_consistency_acknowledgements, [ :entity_id, :fingerprint ], unique: true, name: "index_consistency_acks_on_entity_and_fingerprint"
  end
end

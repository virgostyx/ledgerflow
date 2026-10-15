# B03c: the runs of the check of the integrity of the books (nightly and full), to tell when it last looked and what it found: "Integrity verified today at 03:45".
class CreateIntegrityCheckRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :integrity_check_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :mode, null: false
      t.integer :entries_checked, null: false, default: 0
      t.integer :findings_count, null: false, default: 0
      t.datetime :started_at, null: false, precision: 6
      t.datetime :finished_at, null: false, precision: 6
      t.timestamps
    end
    add_index :integrity_check_runs, %i[entity_id finished_at]
    add_check_constraint :integrity_check_runs, "mode IN ('nightly', 'full')", name: "chk_integrity_runs_mode"
  end
end

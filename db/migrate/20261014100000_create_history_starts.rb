# B03a: from when the books can be shown as they were known (`history_start`). Before that instant a reconstruction is not guaranteed, and the view is refused.
# One row per company, or per company and fiscal year. A company that already had validated entries when the order of validation was added starts at that moment: the
# instants given to what was validated before are the best the database knew, not a proof.
class CreateHistoryStarts < ActiveRecord::Migration[8.1]
  def up
    create_table :accounting_history_starts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fiscal_year, foreign_key: { to_table: :accounting_fiscal_years }
      t.datetime :starts_at, null: false, precision: 6
      t.string :reason
      t.timestamps
    end
    add_index :accounting_history_starts, %i[entity_id fiscal_year_id], unique: true, where: "fiscal_year_id IS NOT NULL", name: "index_history_starts_on_entity_and_year"
    add_index :accounting_history_starts, :entity_id, unique: true, where: "fiscal_year_id IS NULL", name: "index_history_starts_on_entity_alone"
    add_index :accounting_journal_entries, %i[entity_id posted_at], where: "posted_seq IS NOT NULL", name: "index_entries_on_entity_and_posted_at"

    execute <<~SQL
      INSERT INTO accounting_history_starts (entity_id, starts_at, reason, created_at, updated_at)
      SELECT DISTINCT entity_id, now() AT TIME ZONE 'UTC', 'validated entries predate the order of validation', now(), now()
        FROM accounting_journal_entries WHERE posted_at_source = 'backfill'
    SQL
  end

  def down
    remove_index :accounting_journal_entries, name: "index_entries_on_entity_and_posted_at"
    drop_table :accounting_history_starts
  end
end

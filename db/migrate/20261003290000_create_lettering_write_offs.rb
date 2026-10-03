# F04: a lettering that closes with a rounding difference. The adjustment entry is a draft; the lines are lettered, together with the
# adjustment line, when it is validated. This remembers which lines wait for which draft.
class CreateLetteringWriteOffs < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_lettering_write_offs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :journal_entry, null: false, foreign_key: { to_table: :accounting_journal_entries, on_delete: :cascade }, index: { unique: true }
      t.bigint :line_ids, array: true, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :completed_at
      t.timestamps
    end
  end
end

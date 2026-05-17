class CreateAnalyticalAnnotations < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_analytical_annotations do |t|
      t.references :journal_entry_line, null: false,
                   foreign_key: { to_table: :accounting_journal_entry_lines }
      t.references :analytical_axis, null: false,
                   foreign_key: { to_table: :accounting_analytical_axes }
      t.references :analytical_account, null: false,
                   foreign_key: { to_table: :accounting_analytical_accounts }

      t.timestamps
    end

    add_index :accounting_analytical_annotations,
              [ :journal_entry_line_id, :analytical_axis_id ], unique: true,
              name: "index_analytical_annotations_on_line_and_axis"
  end
end

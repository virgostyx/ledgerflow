class CreateAccountingInvoiceLineAnnotations < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_invoice_line_annotations do |t|
      t.references :invoice_line,       null: false,
                   foreign_key: { to_table: :accounting_invoice_lines }
      t.references :analytical_axis,    null: false,
                   foreign_key: { to_table: :accounting_analytical_axes }
      t.references :analytical_account, null: false,
                   foreign_key: { to_table: :accounting_analytical_accounts }
      t.references :entity,             null: false,
                   foreign_key: { to_table: :entities }
      t.timestamps
    end

    add_index :accounting_invoice_line_annotations,
              [ :invoice_line_id, :analytical_axis_id ],
              unique: true,
              name: "idx_invoice_line_annotations_uniqueness"
  end
end

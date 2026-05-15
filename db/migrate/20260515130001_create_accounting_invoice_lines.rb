class CreateAccountingInvoiceLines < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_invoice_lines do |t|
      t.references :invoice, null: false, foreign_key: { to_table: :accounting_invoices }
      t.references :account, null: false, foreign_key: { to_table: :accounting_accounts }

      t.string  :description,      null: false
      t.decimal :quantity,          precision: 10, scale: 3, null: false, default: 1
      t.decimal :unit_price,        precision: 15, scale: 2, null: false, default: 0
      t.decimal :vat_rate,          precision: 5,  scale: 2, null: false, default: 21
      t.integer :vat_code
      t.decimal :subtotal_excl_vat, precision: 15, scale: 2, null: false, default: 0
      t.decimal :vat_amount,        precision: 15, scale: 2, null: false, default: 0
      t.decimal :total_incl_vat,    precision: 15, scale: 2, null: false, default: 0
      t.integer :position,          null: false, default: 1

      t.timestamps
    end

    add_index :accounting_invoice_lines, [ :invoice_id, :position ]
  end
end

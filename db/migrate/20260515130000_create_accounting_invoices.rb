class CreateAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_invoices do |t|
      t.integer    :invoice_type,     null: false, default: 0
      t.integer    :status,           null: false, default: 0
      t.string     :invoice_number
      t.date       :invoice_date,     null: false
      t.date       :due_date
      t.string     :currency,         null: false, default: 'EUR'
      t.decimal    :subtotal_excl_vat, precision: 15, scale: 2, null: false, default: 0
      t.decimal    :vat_amount,        precision: 15, scale: 2, null: false, default: 0
      t.decimal    :total_incl_vat,    precision: 15, scale: 2, null: false, default: 0
      t.text       :description
      t.text       :notes
      t.string     :external_ref
      t.integer    :project_id

      t.references :partner,     null: false, foreign_key: { to_table: :accounting_partners }
      t.references :fiscal_year, null: false, foreign_key: { to_table: :accounting_fiscal_years }
      t.references :journal_entry,       foreign_key: { to_table: :accounting_journal_entries }

      t.timestamps
    end

    add_index :accounting_invoices, :invoice_number, unique: true,
              where: 'invoice_number IS NOT NULL', name: 'index_accounting_invoices_on_invoice_number_unique'
    add_index :accounting_invoices, :status
    add_index :accounting_invoices, :invoice_type
    add_index :accounting_invoices, :invoice_date
  end
end

class AddPeppolFieldsToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :peppol_id,     :string
    add_column :accounting_invoices, :peppol_status, :integer, default: 0, null: false

    add_index :accounting_invoices, :peppol_id, unique: true, where: "peppol_id IS NOT NULL"
  end
end

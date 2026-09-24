class AddCreditNotesToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :document_type, :integer, null: false, default: 0 # invoice: 0, credit_note: 1
    add_reference :accounting_invoices, :credited_invoice, foreign_key: { to_table: :accounting_invoices }
  end
end

class AddVatTreatmentToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :vat_treatment, :integer, null: false, default: 0
  end
end

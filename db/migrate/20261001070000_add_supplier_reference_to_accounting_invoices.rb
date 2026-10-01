# The supplier's own invoice number. `external_ref` is the key a third party addresses the invoice by (API), so it cannot also
# hold this number once BudgetFlow has taken a Peppol invoice over; the number lives here.
class AddSupplierReferenceToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :supplier_reference, :string
    add_index  :accounting_invoices, [ :entity_id, :partner_id, :supplier_reference ], where: "supplier_reference IS NOT NULL",
               name: "index_accounting_invoices_on_entity_partner_supplier_reference"
  end
end

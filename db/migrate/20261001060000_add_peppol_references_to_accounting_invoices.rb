# What a supplier puts on a Peppol invoice to tie it to our side: the purchase order it answers (OrderReference/ID, e.g. a
# BudgetFlow commitment number) and the buyer reference (BuyerReference, e.g. a project code).
class AddPeppolReferencesToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :order_reference, :string
    add_column :accounting_invoices, :buyer_reference, :string
    add_index  :accounting_invoices, [ :entity_id, :order_reference ], where: "order_reference IS NOT NULL",
               name: "index_accounting_invoices_on_entity_and_order_reference"
  end
end

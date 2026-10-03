# F01: who wrote an invoice by hand, for the four-eyes rule. NULL for invoices that nobody typed in the interface
# (API, Peppol, recurring) and for everything that existed before: those are never blocked.
class AddCreatedByToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounting_invoices, :created_by, foreign_key: { to_table: :users }
  end
end

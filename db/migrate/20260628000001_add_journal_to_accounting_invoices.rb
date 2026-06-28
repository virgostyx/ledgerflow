class AddJournalToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounting_invoices, :journal,
                  foreign_key: { to_table: :accounting_journals },
                  null: true
  end
end

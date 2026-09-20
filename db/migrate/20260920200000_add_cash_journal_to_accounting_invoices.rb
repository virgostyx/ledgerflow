class AddCashJournalToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounting_invoices, :cash_journal, foreign_key: { to_table: :accounting_journals }
  end
end

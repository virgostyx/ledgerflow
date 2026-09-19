class AddInvoiceIdToAccountingJournalEntryLines < ActiveRecord::Migration[8.1]
  def up
    add_reference :accounting_journal_entry_lines, :invoice, foreign_key: { to_table: :accounting_invoices }, index: true

    # Receipts booked before this column existed carried the invoice as entry source; move it onto the credit line.
    execute <<~SQL
      UPDATE accounting_journal_entry_lines l
      SET invoice_id = e.source_id
      FROM accounting_journal_entries e
      WHERE l.journal_entry_id = e.id
        AND e.source_type = 'Accounting::InvoiceReceipt'
        AND l.credit > 0
    SQL
  end

  def down
    remove_reference :accounting_journal_entry_lines, :invoice, foreign_key: { to_table: :accounting_invoices }
  end
end

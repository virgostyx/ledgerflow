# F10: a line carried into the next fiscal year keeps the due date it had (an invoice's due date comes from the invoice, but a manual line's from its
# entry date and the partner's terms, and the carried line has a new entry date). Null for every line that has never been carried.
class AddDueDateToJournalEntryLines < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_journal_entry_lines, :due_date, :date
  end
end

class MakeJournalEntryReferenceNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :accounting_journal_entries, :reference, true
  end
end

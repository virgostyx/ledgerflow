# The entry that closes a fiscal year is now marked (source_type), so that the annual accounts can read the income of a
# closed year without it. Marks the ones already made, recognised by their description.
class MarkExistingClosingEntries < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE accounting_journal_entries SET source_type = 'Accounting::ClosingEntry'
      WHERE source_type IS NULL AND description LIKE 'Closing entry for fiscal year %'
    SQL
  end

  def down
    execute "UPDATE accounting_journal_entries SET source_type = NULL WHERE source_type = 'Accounting::ClosingEntry'"
  end
end

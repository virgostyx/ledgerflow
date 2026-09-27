class AddEntryDateToJournalEntryLines < ActiveRecord::Migration[8.1]
  # Denormalizes accounting_journal_entries.entry_date onto each line
  # (docs/dev/reports/spec.md §3), kept in sync by Accounting::JournalEntryLine's
  # before_validation callback. Backfilled here for existing rows; a single
  # UPDATE...FROM is fine at this app's current data volume — batch it if the
  # reports spec's 200k-row performance target ever makes this migration slow.
  def up
    add_column :accounting_journal_entry_lines, :entry_date, :date

    execute <<~SQL
      UPDATE accounting_journal_entry_lines l
      SET entry_date = e.entry_date
      FROM accounting_journal_entries e
      WHERE e.id = l.journal_entry_id AND l.entry_date IS NULL;
    SQL
  end

  def down
    remove_column :accounting_journal_entry_lines, :entry_date
  end
end

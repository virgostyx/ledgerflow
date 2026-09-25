class AddDisposalJournalEntryToAccountingFixedAssets < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounting_fixed_assets, :disposal_journal_entry, foreign_key: { to_table: :accounting_journal_entries }
  end
end

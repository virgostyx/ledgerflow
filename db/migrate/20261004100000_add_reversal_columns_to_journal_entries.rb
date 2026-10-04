# F07: a reversal keeps its reason (the audit row of the original is written when the reversal is posted, by whoever posts it), may be
# marked as a VAT regularisation, and an entry may ask for its own reversal on a date (auto_reverse_on, as a draft).
class AddReversalColumnsToJournalEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_journal_entries, :auto_reverse_on, :date
    add_column :accounting_journal_entries, :reversal_reason, :string
    add_column :accounting_journal_entries, :vat_regularisation, :boolean, null: false, default: false
    add_index  :accounting_journal_entries, :auto_reverse_on, where: "auto_reverse_on IS NOT NULL", name: "idx_entries_auto_reverse_on"
  end
end

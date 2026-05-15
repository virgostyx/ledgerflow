class AddPartnerFkToJournalEntryLines < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :accounting_journal_entry_lines, :accounting_partners,
                    column: :partner_id
  end
end

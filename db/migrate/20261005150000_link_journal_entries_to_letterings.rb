# F11: the exchange difference that a lettering generates is an entry linked to that lettering, so that undoing the lettering finds it and undoes it too.
class LinkJournalEntriesToLetterings < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounting_journal_entries, :lettering, foreign_key: { to_table: :accounting_letterings, on_delete: :nullify }
  end
end

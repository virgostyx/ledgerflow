class CreateAccountingJournalEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_journal_entries do |t|
      t.references :journal,     null: false,
                   foreign_key:  { to_table: :accounting_journals }
      t.references :fiscal_year, null: false,
                   foreign_key:  { to_table: :accounting_fiscal_years }

      t.date    :entry_date,   null: false
      t.string  :reference,    null: false
      t.string  :description
      t.integer :status,       null: false, default: 0  # draft(0)/posted(1)/reversed(2)

      t.string  :source_type
      t.bigint  :source_id
      t.bigint  :reversal_of_id

      t.integer :project_id   # ID BudgetFlow — pas de FK (app séparée)
      t.string  :external_ref

      t.string  :locked_by
      t.datetime :locked_at

      t.timestamps
    end

    add_index :accounting_journal_entries, :reference,                unique: true
    add_index :accounting_journal_entries, [ :source_type, :source_id ]
    add_index :accounting_journal_entries, :project_id
    add_index :accounting_journal_entries, :status
    add_index :accounting_journal_entries, :entry_date
  end
end

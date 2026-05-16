class CreateAccountingBankTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_bank_transactions do |t|
      t.references :bank_account, null: false,
                   foreign_key: { to_table: :accounting_bank_accounts }
      t.references :journal_entry,
                   foreign_key: { to_table: :accounting_journal_entries }
      t.date    :transaction_date, null: false
      t.date    :value_date
      t.decimal :amount,    precision: 15, scale: 2, null: false
      t.string  :currency,  null: false, default: 'EUR'
      t.string  :description
      t.string  :reference
      t.integer :status,    null: false, default: 0
      t.jsonb   :raw_data,  null: false, default: {}

      t.timestamps
    end

    add_index :accounting_bank_transactions, [ :bank_account_id, :reference ],
              unique: true, where: "reference IS NOT NULL",
              name: "idx_bank_transactions_on_account_and_ref"
  end
end

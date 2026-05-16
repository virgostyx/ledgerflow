class CreateAccountingBankAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_bank_accounts do |t|
      t.references :journal, null: false,
                   foreign_key: { to_table: :accounting_journals }
      t.string  :iban,      null: false
      t.string  :bic
      t.string  :label_fr,  null: false
      t.string  :currency,  null: false, default: 'EUR'
      t.decimal :balance,   precision: 15, scale: 2, null: false, default: 0
      t.boolean :active,    null: false, default: true

      t.timestamps
    end

    add_index :accounting_bank_accounts, :iban, unique: true
  end
end

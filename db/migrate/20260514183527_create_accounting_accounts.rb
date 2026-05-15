class CreateAccountingAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_accounts do |t|
      t.string  :code,            null: false, limit: 10
      t.string  :label_fr,        null: false
      t.string  :label_nl
      t.integer :account_class,   null: false  # 1..7
      t.integer :account_type,    null: false  # asset/liability/equity/revenue/expense
      t.integer :normal_balance,  null: false  # debit/credit
      t.boolean :reconcilable,    null: false, default: false
      t.boolean :active,          null: false, default: true
      t.boolean :is_leaf,         null: false, default: true
      t.integer :vat_code_default
      t.bigint  :parent_id
      t.decimal :balance_debit,   precision: 15, scale: 2, default: 0
      t.decimal :balance_credit,  precision: 15, scale: 2, default: 0
      t.timestamps
    end

    add_index :accounting_accounts, :code,          unique: true
    add_index :accounting_accounts, :parent_id
    add_index :accounting_accounts, :account_class
    add_index :accounting_accounts, :active

    execute <<~SQL
      ALTER TABLE accounting_accounts
        ADD CONSTRAINT chk_account_class
        CHECK (account_class BETWEEN 1 AND 7);
    SQL
  end
end

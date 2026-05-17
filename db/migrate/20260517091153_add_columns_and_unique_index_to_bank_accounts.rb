class AddColumnsAndUniqueIndexToBankAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_bank_accounts, :label_nl, :string
    add_column :accounting_bank_accounts, :notes,    :text

    remove_index :accounting_bank_accounts, :journal_id
    add_index    :accounting_bank_accounts, :journal_id, unique: true
  end
end

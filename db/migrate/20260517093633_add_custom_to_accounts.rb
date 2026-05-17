class AddCustomToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_accounts, :custom, :boolean, default: false, null: false
  end
end

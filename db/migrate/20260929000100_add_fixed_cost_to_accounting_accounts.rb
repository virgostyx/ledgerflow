class AddFixedCostToAccountingAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_accounts, :fixed_cost, :boolean, default: false, null: false
  end
end

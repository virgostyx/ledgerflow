# R15 (spec §12): optional per-account override of the cash-flow category used by the direct
# method. NULL = the default by account-code family (Accounting::CashFlowCategories).
class AddCashFlowCategoryToAccountingAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_accounts, :cash_flow_category, :string
  end
end

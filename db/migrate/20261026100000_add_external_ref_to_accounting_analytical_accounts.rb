# Analytical accounts that a third-party application (BudgetFlow) creates and keeps: the key under which it knows each one
# (unique per entity) and the group it belongs to (its project), so the ones it drops can be deactivated. A code gets longer:
# a budget line is "<project code>-<chapter>.<line>.<sub line>".
class AddExternalRefToAccountingAnalyticalAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :accounting_analytical_accounts, :external_ref, :string
    add_column :accounting_analytical_accounts, :external_group, :string
    add_index :accounting_analytical_accounts, [ :entity_id, :external_ref ], unique: true,
              where: "external_ref IS NOT NULL", name: "index_analytical_accounts_on_entity_and_external_ref"
    change_column :accounting_analytical_accounts, :code, :string, limit: 40
  end

  # Fails, on purpose, if a code longer than 20 characters exists: shortening it would change accounting data.
  def down
    change_column :accounting_analytical_accounts, :code, :string, limit: 20
    remove_index :accounting_analytical_accounts, name: "index_analytical_accounts_on_entity_and_external_ref"
    remove_column :accounting_analytical_accounts, :external_group
    remove_column :accounting_analytical_accounts, :external_ref
  end
end

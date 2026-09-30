# The BudgetFlow integration (third-party API, BudgetFlow invoice queue, payment feed) is opt-in per entity: an entity
# that did not declare it is not influenced by it and does not see it.
class AddBudgetflowEnabledToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :budgetflow_enabled, :boolean, null: false, default: false
  end
end

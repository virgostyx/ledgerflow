# Key under which a third-party application (BudgetFlow) knows the partner; unique per entity.
class AddExternalRefToAccountingPartners < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_partners, :external_ref, :string
    add_index :accounting_partners, [ :entity_id, :external_ref ], unique: true,
              where: "external_ref IS NOT NULL", name: "index_accounting_partners_on_entity_and_external_ref"
  end
end

# F04: lets the nightly job letter, without a person, the suggestions that are certain (score 100). Off by default.
class AddAutoReconcileExactToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :auto_reconcile_exact, :boolean, null: false, default: false
  end
end

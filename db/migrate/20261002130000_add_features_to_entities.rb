# Per-entity feature flags (feature_f01 ... feature_f13 of docs/dev/features/spec.md): off unless the owner turns one on.
class AddFeaturesToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :features, :jsonb, null: false, default: {}
  end
end

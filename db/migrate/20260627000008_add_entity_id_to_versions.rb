class AddEntityIdToVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :versions, :entity_id, :bigint
    add_index :versions, :entity_id, name: "index_versions_on_entity_id"
  end
end

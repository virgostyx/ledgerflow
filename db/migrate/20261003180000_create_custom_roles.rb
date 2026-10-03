# F01: roles an owner composes from the fine permissions of Permissions::MATRIX (spec §4), and the access that holds one.
class CreateCustomRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_roles do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false
      t.text   :permissions, array: true, null: false, default: []
      t.timestamps
    end
    add_index :custom_roles, %i[entity_id name], unique: true

    add_reference :user_entities, :custom_role, foreign_key: { to_table: :custom_roles, on_delete: :restrict }
  end
end

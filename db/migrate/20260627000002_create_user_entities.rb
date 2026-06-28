class CreateUserEntities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_entities do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.integer    :role,   null: false, default: 0
      t.boolean    :active, null: false, default: true

      t.timestamps
    end

    add_index :user_entities, %i[user_id entity_id], unique: true,
              name: "index_user_entities_on_user_and_entity"
  end
end

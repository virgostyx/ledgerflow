class AddValidityWindowToUserEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :user_entities, :valid_from,  :date
    add_column :user_entities, :valid_until, :date
  end
end

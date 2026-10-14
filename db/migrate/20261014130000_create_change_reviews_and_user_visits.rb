# B03b: a reviewer marks a change as reviewed (`accounting_change_reviews`: one row per change, visible to everyone of the company), and the last visit of a person to the
# report of changes (`accounting_user_visits`) proposes the default T1. The visit is personal: the person sees it and erases it, the company can switch it off.
class CreateChangeReviewsAndUserVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_change_reviews do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :change_key, null: false
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.datetime :reviewed_at, null: false, precision: 6
      t.text :comment
      t.timestamps
    end
    add_index :accounting_change_reviews, %i[entity_id change_key], unique: true

    create_table :accounting_user_visits do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :visited_at, null: false, precision: 6
      t.timestamps
    end
    add_index :accounting_user_visits, %i[entity_id user_id], unique: true

    add_column :entities, :track_visits, :boolean, null: false, default: true
  end
end

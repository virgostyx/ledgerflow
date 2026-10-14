# B03b: the thresholds of the review alerts are the company's (the defaults are the specification's), and a person can subscribe to the alerts that matter to them
# (`accounting_change_subscriptions`: the kinds, and when they were last told, so that they get one notification a day, never one per entry).
class AddChangesSettingsAndSubscriptions < ActiveRecord::Migration[8.1]
  def change
    change_table :entities, bulk: true do |t|
      t.integer :changes_late_days, null: false, default: 15
      t.integer :changes_reversals_per_author, null: false, default: 5
      t.integer :changes_mass_import, null: false, default: 50
      t.integer :changes_unletterings, null: false, default: 3
    end

    create_table :accounting_change_subscriptions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :kinds, array: true, null: false, default: []
      t.datetime :last_notified_at, precision: 6
      t.timestamps
    end
    add_index :accounting_change_subscriptions, %i[entity_id user_id], unique: true
  end
end

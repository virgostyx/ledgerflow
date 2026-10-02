# F01: four-eyes control. The author of a manual entry is kept; an entity may require another person to validate
# (from an optional amount upward).
class AddFourEyes < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounting_journal_entries, :created_by, foreign_key: { to_table: :users }
    add_column :entities, :four_eyes, :boolean, null: false, default: false
    add_column :entities, :four_eyes_threshold, :decimal, precision: 15, scale: 2
  end
end

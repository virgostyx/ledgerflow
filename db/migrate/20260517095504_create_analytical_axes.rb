class CreateAnalyticalAxes < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_analytical_axes do |t|
      t.string  :code,     null: false, limit: 10
      t.string  :label_fr, null: false
      t.string  :label_nl
      t.boolean :active,   null: false, default: true
      t.integer :required_for_account_classes, array: true, default: []

      t.timestamps
    end

    add_index :accounting_analytical_axes, :code, unique: true
  end
end

class CreateAnalyticalAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_analytical_accounts do |t|
      t.references :analytical_axis, null: false,
                   foreign_key: { to_table: :accounting_analytical_axes }
      t.string  :code,     null: false, limit: 20
      t.string  :label_fr, null: false
      t.string  :label_nl
      t.boolean :active,   null: false, default: true

      t.timestamps
    end

    add_index :accounting_analytical_accounts, [ :analytical_axis_id, :code ], unique: true,
              name: "index_analytical_accounts_on_axis_and_code"
  end
end

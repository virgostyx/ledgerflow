class CreateAccountingFixedAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_fixed_assets do |t|
      t.string  :description, null: false
      t.date    :acquisition_date, null: false
      t.decimal :vat_amount_initial, precision: 15, scale: 2, null: false
      t.decimal :prorata_at_acquisition, precision: 5, scale: 2, null: false, default: 100.0
      t.integer :asset_category, null: false, default: 0 # movable: 0, immovable: 1
      t.date    :disposed_on
      t.references :invoice_line, foreign_key: { to_table: :accounting_invoice_lines }, null: true
      t.references :entity, null: false, foreign_key: true

      t.timestamps
    end
  end
end

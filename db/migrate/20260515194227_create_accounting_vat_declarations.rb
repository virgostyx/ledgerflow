class CreateAccountingVatDeclarations < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_vat_declarations do |t|
      t.references :fiscal_year, null: false,
                   foreign_key: { to_table: :accounting_fiscal_years }
      t.integer :status,      null: false, default: 0
      t.integer :period_type, null: false, default: 0
      t.date    :period_start, null: false
      t.date    :period_end,   null: false
      t.jsonb   :grids, null: false, default: {}

      t.timestamps
    end
  end
end

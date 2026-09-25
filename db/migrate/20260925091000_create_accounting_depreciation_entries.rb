class CreateAccountingDepreciationEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_depreciation_entries do |t|
      t.references :entity,        null: false, foreign_key: true
      t.references :fixed_asset,   null: false, foreign_key: { to_table: :accounting_fixed_assets }
      t.references :fiscal_year,   null: false, foreign_key: { to_table: :accounting_fiscal_years }
      t.references :journal_entry, null: false, foreign_key: { to_table: :accounting_journal_entries }
      t.decimal :amount, precision: 15, scale: 2, null: false

      t.timestamps
    end

    add_index :accounting_depreciation_entries, %i[fixed_asset_id fiscal_year_id], unique: true,
              name: "index_depreciation_entries_on_asset_and_fiscal_year"
  end
end

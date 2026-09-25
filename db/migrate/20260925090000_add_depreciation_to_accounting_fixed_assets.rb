class AddDepreciationToAccountingFixedAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_fixed_assets, :acquisition_value, :decimal, precision: 15, scale: 2
    add_reference :accounting_fixed_assets, :asset_account, foreign_key: { to_table: :accounting_accounts }
    add_column :accounting_fixed_assets, :in_service_date, :date
    add_column :accounting_fixed_assets, :useful_life_years, :integer
    add_column :accounting_fixed_assets, :residual_value, :decimal, precision: 15, scale: 2, null: false, default: 0
    add_column :accounting_fixed_assets, :depreciation_method, :integer, null: false, default: 0 # linear: 0
    change_column_default :accounting_fixed_assets, :vat_amount_initial, from: nil, to: 0
  end
end

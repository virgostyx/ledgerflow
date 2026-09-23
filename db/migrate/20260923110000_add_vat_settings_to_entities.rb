class AddVatSettingsToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :vat_filing_frequency, :integer, null: false, default: 1 # quarterly
    add_column :entities, :vat_regime, :integer, null: false, default: 0 # normal
  end
end

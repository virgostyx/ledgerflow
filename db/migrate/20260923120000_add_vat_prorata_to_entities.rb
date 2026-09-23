class AddVatProrataToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :vat_scheme, :integer, null: false, default: 0 # normal
    add_column :entities, :vat_prorata_rate, :decimal, precision: 5, scale: 2 # e.g. 80.00 = 80%; nil = full deduction
  end
end

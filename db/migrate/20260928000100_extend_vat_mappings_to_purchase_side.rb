class ExtendVatMappingsToPurchaseSide < ActiveRecord::Migration[8.1]
  # Phase 2 of the VAT normalization (docs/dev/reports/spec.md §10): the purchase side too, so
  # Accounting::VatGrid can read every grid decision from data. The purchase base grids 81-83
  # depend on the expense account's prefix (notice n°149-156), a dimension vat_code x document
  # type doesn't have — hence the separate rules table.
  def change
    add_column :accounting_vat_grid_mappings, :deductible_vat_grid, :integer
    # Recap grid a credit-note amount is also shown in (84/85, notice n°166-175); null = none.
    add_column :accounting_vat_grid_mappings, :credit_note_recap_grid, :integer

    create_table :accounting_vat_account_grid_rules do |t|
      t.integer :sens, null: false            # 1 = purchase
      t.string  :account_prefix, null: false  # longest matching prefix wins
      t.integer :base_grid, null: false
      t.integer :credit_note_recap_grid
      t.timestamps
    end
    add_index :accounting_vat_account_grid_rules, [ :sens, :account_prefix ], unique: true,
              name: "idx_vat_account_grid_rules_sens_prefix"
  end
end

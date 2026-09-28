class CreateVatCodesAndGridMappings < ActiveRecord::Migration[8.1]
  # docs/dev/reports/spec.md §10: vat_codes + vat_grid_mappings, data-driven instead of
  # hardcoded — scoped to the SALE side only (user's call, 2026-09-28): the purchase side
  # mixes an account-prefix-driven rule (81/82/83, notice n°149-156) with code-driven
  # grids, and stays as Accounting::VatGrid Ruby constants to avoid touching that more
  # entangled, already-correct logic. Not tenant-scoped: VAT law, not per-entity data.
  def change
    create_table :accounting_vat_codes do |t|
      t.string  :code,  null: false
      t.string  :label, null: false
      t.integer :sens,  null: false # 0 = sale (only value used for now)
      t.integer :nature, null: false # domestic/intracom_goods/intracom_services/construction_reverse_charge/export/exempt
      t.decimal :rate, precision: 5, scale: 2 # null for a non-domestic nature (rate doesn't drive its grid)
      t.timestamps
    end
    add_index :accounting_vat_codes, :code, unique: true

    create_table :accounting_vat_grid_mappings do |t|
      t.references :vat_code, null: false, foreign_key: { to_table: :accounting_vat_codes }
      t.integer :document_type, null: false # 0 = invoice, 1 = credit_note
      t.integer :base_grid
      t.integer :due_vat_grid
      t.timestamps
    end
    add_index :accounting_vat_grid_mappings, [ :vat_code_id, :document_type ], unique: true,
              name: "idx_vat_grid_mappings_code_doctype"
  end
end

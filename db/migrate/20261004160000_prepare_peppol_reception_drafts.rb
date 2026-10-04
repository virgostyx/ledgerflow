# F06 step 3: what a received invoice needs to become a draft worth validating.
# - partners.to_validate: a supplier created from a received document waits for a person to look at it (never created as validated)
# - invoices.payment_reference: the supplier's payment reference (structured communication) kept for the bank matching (F02, F04)
# - vat_category_mappings: UBL VAT category -> VAT treatment of the entity (editable data, nothing hard-coded)
# - supplier_defaults: the last expense account (and journal, terms) used for a supplier, which feeds the account proposals
class PreparePeppolReceptionDrafts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_partners, :to_validate, :boolean, null: false, default: false
    add_column :accounting_invoices, :payment_reference, :string

    create_table :accounting_vat_category_mappings do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :category, null: false                 # UBL: S, Z, E, AE, K, G, O
      t.integer :vat_treatment, null: false, default: 0 # as Accounting::Invoice#vat_treatment
      t.decimal :vat_rate, precision: 5, scale: 2       # nil: the rate of the document; set: the rate to self-assess (reverse charge)
      t.timestamps
    end
    add_index :accounting_vat_category_mappings, %i[entity_id category], unique: true

    create_table :accounting_supplier_defaults do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :partner, null: false, foreign_key: { to_table: :accounting_partners, on_delete: :cascade }, index: { unique: true }
      t.references :account, foreign_key: { to_table: :accounting_accounts }
      t.references :journal, foreign_key: { to_table: :accounting_journals }
      t.integer :vat_treatment
      t.integer :payment_terms_days
      t.timestamps
    end
  end
end

# F02: the entity's own rules for bank lines (bank fees, insurance, rent...): a condition, what to book it on, and whether the
# engine only proposes it or books it as a draft.
class CreateAccountingBankRules < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_bank_rules do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :condition_type, null: false            # contains / iban / amount
      t.string  :condition_value, null: false
      t.references :account, null: false, foreign_key: { to_table: :accounting_accounts }
      t.references :partner, foreign_key: { to_table: :accounting_partners }
      t.string  :vat_code
      t.string  :action, null: false, default: "propose" # propose / book_draft
      t.integer :priority, null: false, default: 100     # lowest first
      t.integer :score, null: false, default: 80         # the confidence it gives (1 to 99)
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :accounting_bank_rules, %i[entity_id active priority]
  end
end

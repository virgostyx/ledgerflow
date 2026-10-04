# F07: entry templates (a journal and model lines: account, optional partner, debit or credit, fixed amount, percentage of an amount asked
# once, or an amount typed per line; labels with variables). Recurring entries are built from them.
class CreateEntryTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_entry_templates do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false
      t.references :journal, null: false, foreign_key: { to_table: :accounting_journals }
      t.string :description
      t.timestamps
    end
    add_index :accounting_entry_templates, %i[entity_id name], unique: true

    create_table :accounting_entry_template_lines do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :entry_template, null: false, foreign_key: { to_table: :accounting_entry_templates, on_delete: :cascade }
      t.references :account, null: false, foreign_key: { to_table: :accounting_accounts }
      t.references :partner, foreign_key: { to_table: :accounting_partners }
      t.integer :side, null: false          # debit / credit
      t.integer :amount_kind, null: false   # fixed / percent / input
      t.decimal :amount, precision: 15, scale: 2
      t.decimal :percentage, precision: 7, scale: 3
      t.integer :vat_code
      t.string  :label
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end

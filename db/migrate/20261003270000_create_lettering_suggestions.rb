# F04: proposed letterings. One row per group of lines (fingerprint of the lines and their amounts): a rejected group is not
# proposed again until one of its lines changes, since the fingerprint then changes too.
class CreateLetteringSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_lettering_suggestions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: { to_table: :accounting_accounts }
      t.references :partner, foreign_key: { to_table: :accounting_partners }
      t.bigint  :line_ids, array: true, null: false
      t.integer :score, null: false
      t.integer :rule, null: false
      t.integer :status, null: false, default: 0 # proposed / accepted / rejected
      t.string  :fingerprint, null: false
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.timestamps
    end
    add_index :accounting_lettering_suggestions, %i[entity_id fingerprint], unique: true
    add_index :accounting_lettering_suggestions, %i[entity_id status score]
  end
end

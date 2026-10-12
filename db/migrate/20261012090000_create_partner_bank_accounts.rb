# B01b: the bank accounts a supplier is paid on, kept apart from the IBAN written on the partner record (which stays what it is: information).
# A new or changed account starts unverified and is observed for some hours; someone else verifies it. The IBAN is encrypted at rest.
# Also: how long the observation lasts (24 hours by default), and the IBAN written on a purchase invoice, to be compared with the verified account. Additive and reversible.
class CreatePartnerBankAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :partner_bank_accounts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :partner, null: false, foreign_key: { to_table: :accounting_partners }
      t.string  :iban, null: false # encrypted, deterministic
      t.string  :bic
      t.string  :holder_name, null: false
      t.integer :status, null: false, default: 0 # unverified, verified, blocked, superseded
      t.integer :source, null: false, default: 0 # manual, invoice, import
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :verified_by, foreign_key: { to_table: :users }
      t.datetime :verified_at
      t.integer  :verification_method # phone_callback, signed_letter, supplier_statement, other
      t.text     :verification_note
      t.string   :blocked_reason
      t.datetime :first_seen_at, null: false
      t.datetime :cooling_until, null: false
      t.references :previous_account, foreign_key: { to_table: :partner_bank_accounts }
      t.timestamps
    end
    add_index :partner_bank_accounts, %i[partner_id status]
    add_index :partner_bank_accounts, %i[partner_id iban], unique: true, where: "status IN (0, 1, 2)", name: "index_partner_bank_accounts_one_live_iban_per_partner"

    add_column :entities, :iban_cooling_hours, :integer, null: false, default: 24
    add_column :accounting_invoices, :iban, :string # as written on the document, encrypted
  end
end

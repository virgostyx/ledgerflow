# B01b: the payment batches of the new flow, beside the earlier accounting_payment_batches (kept as they are, for the batches that exist). A batch has its
# payments (one per supplier, with a snapshot of the account paid); a payment pays one or several invoices (or a part of one); a bill is in one active batch at most,
# which the database guarantees. Plus the holds on an invoice or a supplier, and the profile of a bank. Additive and reversible.
class CreatePaymentBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_bank_profiles do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :format_version, null: false # from the documentation of the bank, never guessed
      t.string  :encoding, null: false, default: "UTF-8"
      t.jsonb   :options, null: false, default: {}
      t.integer :max_payments
      t.boolean :format_verified, null: false, default: false # the bank was seen to take this file
      t.boolean :coda_verified, null: false, default: false   # the CODA of this bank was seen, so the batch can be recognised on the statement
      t.timestamps
    end

    create_table :payment_batches do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :bank_account, null: false, foreign_key: { to_table: :accounting_bank_accounts } # the account debited
      t.references :bank_profile, foreign_key: { to_table: :payment_bank_profiles }
      t.string  :reference, null: false
      t.integer :status, null: false, default: 0 # draft pending_approval approved exported submitted debited partially_rejected cancelled cancel_requested
      t.date    :requested_execution_date, null: false
      t.decimal :total, precision: 15, scale: 2, null: false, default: 0
      t.integer :payments_count, null: false, default: 0
      t.decimal :control_sum, precision: 15, scale: 2 # of the file, equal to the total
      t.string  :message_id
      t.string  :format_version
      t.string  :file_sha256, limit: 64
      t.references :document, foreign_key: { to_table: :accounting_documents }
      t.references :prepared_by, foreign_key: { to_table: :users }
      t.datetime :prepared_at
      t.references :exported_by, foreign_key: { to_table: :users }
      t.datetime :exported_at
      t.references :submitted_by, foreign_key: { to_table: :users }
      t.datetime :submitted_at
      t.references :cancelled_by, foreign_key: { to_table: :users }
      t.datetime :cancelled_at
      t.string :cancel_reason
      t.references :approval_request, foreign_key: { to_table: :approval_requests }
      t.jsonb :preflight_report, null: false, default: {}
      t.timestamps
    end
    add_index :payment_batches, %i[entity_id reference], unique: true

    create_table :payment_items do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :batch, null: false, foreign_key: { to_table: :payment_batches, on_delete: :cascade }
      t.references :partner, null: false, foreign_key: { to_table: :accounting_partners }
      t.references :partner_bank_account, foreign_key: { to_table: :partner_bank_accounts }
      t.string  :iban, null: false # snapshot of the account paid, encrypted
      t.string  :bic
      t.string  :holder_name, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string  :currency, null: false, default: "EUR"
      t.string  :end_to_end_id, null: false, limit: 35
      t.string  :remittance
      t.boolean :structured_remittance, null: false, default: false
      t.integer :status, null: false, default: 0 # included excluded confirmed rejected returned
      t.string  :exclusion_reason
      t.references :journal_entry, foreign_key: { to_table: :accounting_journal_entries } # the entry of the payment, once confirmed (B01c)
      t.timestamps
    end
    add_index :payment_items, %i[batch_id end_to_end_id], unique: true

    create_table :payment_item_invoices do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: { to_table: :payment_items, on_delete: :cascade }
      t.references :invoice, null: false, foreign_key: { to_table: :accounting_invoices }
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.boolean :active, null: false, default: true # the batch is active and the payment is included
      t.timestamps
    end
    add_index :payment_item_invoices, :invoice_id, unique: true, where: "active", name: "index_payment_item_invoices_one_active_batch_per_invoice"

    create_table :payment_holds do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :invoice, foreign_key: { to_table: :accounting_invoices }
      t.references :partner, foreign_key: { to_table: :accounting_partners }
      t.string :reason, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :released_at
      t.references :released_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end

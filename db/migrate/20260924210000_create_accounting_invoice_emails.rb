class CreateAccountingInvoiceEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_invoice_emails do |t|
      t.references :entity,  null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: { to_table: :accounting_invoices }
      t.references :sent_by, null: false, foreign_key: { to_table: :users }
      t.string   :recipient, null: false
      t.string   :subject,   null: false
      t.integer  :status,    null: false, default: 0 # queued: 0, sent: 1, failed: 2
      t.text     :error
      t.datetime :sent_at

      t.timestamps
    end
  end
end

# Payment events of API-managed invoices (paid, partially paid, payment undone), appended when the invoice status
# moves, and read by the third-party application through GET /api/v1/invoice_events (docs/dev/api/inbound-api.md).
class CreateAccountingInvoiceEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_invoice_events do |t|
      t.bigint   :entity_id, null: false
      t.bigint   :invoice_id, null: false
      t.string   :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb    :payload, null: false, default: {}
      t.timestamps
    end
    add_index :accounting_invoice_events, [ :entity_id, :id ]
    add_index :accounting_invoice_events, :invoice_id
    add_foreign_key :accounting_invoice_events, :entities
    add_foreign_key :accounting_invoice_events, :accounting_invoices, column: :invoice_id
  end
end

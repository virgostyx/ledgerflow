# F06 step 1: every message that goes through the Peppol network (in or out) is recorded, with its XML, whatever becomes of it. Unique per
# entity, direction and message identifier: a message delivered twice is one record. The XML is kept here first (the document store may
# refuse a file); `problems` are the reasons a message waits for a person (needs_review).
class CreateAccountingPeppolMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_peppol_messages do |t|
      t.references :entity, null: false, foreign_key: true
      t.integer :direction, null: false                  # inbound / outbound
      t.string  :message_id, null: false                 # the Access Point's identifier, or sha256:<digest of the XML>
      t.string  :sender_id
      t.string  :receiver_id
      t.integer :document_type, null: false, default: 0  # invoice / credit_note / other
      t.string  :process
      t.integer :status, null: false, default: 0         # received / processed / needs_review / queued / delivered / failed
      t.text    :xml
      t.jsonb   :problems, null: false, default: []
      t.string  :note
      t.datetime :occurred_at, null: false
      t.references :invoice, foreign_key: { to_table: :accounting_invoices, on_delete: :nullify }
      t.references :document, foreign_key: { to_table: :accounting_documents, on_delete: :nullify }
      t.timestamps
    end
    add_index :accounting_peppol_messages, %i[entity_id direction message_id], unique: true, name: "idx_peppol_messages_identity"
    add_index :accounting_peppol_messages, %i[entity_id status]
  end
end

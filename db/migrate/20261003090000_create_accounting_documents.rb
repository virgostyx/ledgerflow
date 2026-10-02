# F03: supporting documents. The file itself is an Active Storage attachment, never modified; a new version is a new
# document that points to the old one (replaces_id). unaccent / pg_trgm serve the full-text search and, later,
# the bank matching (F02).
class CreateAccountingDocuments < ActiveRecord::Migration[8.1]
  def change
    enable_extension "unaccent"
    enable_extension "pg_trgm"

    create_table :accounting_documents do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :content_type
      t.bigint  :byte_size, null: false
      t.string  :sha256, null: false, limit: 64
      t.integer :origin, null: false, default: 0  # manual_upload, email, peppol, bank_import, scan
      t.integer :kind,   null: false, default: 0  # other, purchase_invoice, sales_invoice, credit_note, statement, contract
      t.integer :status, null: false, default: 0  # inbox, linked, archived
      t.text    :search_text
      t.jsonb   :extracted_data, null: false, default: {}
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.date    :retention_until
      t.boolean :legal_hold, null: false, default: false
      t.references :replaces, foreign_key: { to_table: :accounting_documents }
      t.timestamps
    end
    add_index :accounting_documents, %i[entity_id sha256], unique: true, name: "idx_documents_entity_sha256"
    add_index :accounting_documents, %i[entity_id status created_at], name: "idx_documents_entity_status"

    create_table :accounting_document_links do |t|
      t.references :document, null: false, foreign_key: { to_table: :accounting_documents }
      t.string :target_type, null: false
      t.bigint :target_id,   null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :accounting_document_links, %i[document_id target_type target_id], unique: true, name: "idx_document_links_unique"
    add_index :accounting_document_links, %i[target_type target_id], name: "idx_document_links_target"
  end
end

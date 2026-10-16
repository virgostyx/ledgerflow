# B02b: the firm asks a client for the supporting documents of bank lines. What the client may see of a line is copied here at the request (date, cleaned label, amount): the portal reads
# portal_* only, and never the counterparty's IBAN.
class CreatePortalDocumentRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :entities, :portal_show_bank_lines, :boolean, null: false, default: true

    create_table :portal_document_requests do |t|
      t.string :token, null: false
      t.references :entity, null: false, foreign_key: true
      t.text :message
      t.date :due_on
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.date :last_reminder_on
      t.timestamps
    end
    add_index :portal_document_requests, :token, unique: true

    create_table :portal_document_request_lines do |t|
      t.references :request, null: false, foreign_key: { to_table: :portal_document_requests }
      t.references :entity, null: false, foreign_key: true
      t.string :token, null: false
      t.bigint :bank_transaction_id, null: false # the firm's side only: the portal never follows it
      t.date :line_date, null: false
      t.string :label
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string :currency, null: false, default: "EUR"
      t.string :state, null: false, default: "open"
      t.references :answered_by, foreign_key: { to_table: :portal_users }
      t.datetime :answered_at
      t.string :answer_reason
      t.string :answer_note
      t.bigint :task_id # the task the answer opened for the accountant (firm's side)
      t.string :withdrawn_reason
      t.timestamps
    end
    add_index :portal_document_request_lines, :token, unique: true
    add_index :portal_document_request_lines, %i[entity_id state]

    add_column :portal_uploads, :request_line_id, :bigint # the line a document was sent for, when it was

    execute <<~SQL
      CREATE OR REPLACE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled,
               COALESCE((features ->> 'b02a')::boolean, false) AND COALESCE((features ->> 'b02b')::boolean, false) AND COALESCE((features ->> 'f03')::boolean, false) AS upload_enabled,
               portal_show_bank_lines AS show_bank_lines
        FROM entities
    SQL
  end

  def down
    execute <<~SQL
      DROP VIEW portal_companies;
      CREATE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled,
               COALESCE((features ->> 'b02a')::boolean, false) AND COALESCE((features ->> 'b02b')::boolean, false) AND COALESCE((features ->> 'f03')::boolean, false) AS upload_enabled
        FROM entities
    SQL
    remove_column :portal_uploads, :request_line_id
    drop_table :portal_document_request_lines
    drop_table :portal_document_requests
    remove_column :entities, :portal_show_bank_lines
  end
end

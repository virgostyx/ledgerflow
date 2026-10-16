# B02b: what a person from outside sends to the firm. An upload is received in chunks (resumable, a chunk replayed changes nothing) and stays in quarantine until the firm's
# side has checked it (Portal::Upload#status); the portal itself never creates a document of the books.
class CreatePortalUploads < ActiveRecord::Migration[8.1]
  def up
    create_table :portal_uploads do |t|
      t.string :token, null: false
      t.references :entity, null: false, foreign_key: true
      t.references :portal_user, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :content_type
      t.bigint :byte_size, null: false
      t.string :sha256, null: false
      t.integer :chunk_size, null: false
      t.integer :chunk_count, null: false
      t.string :status, null: false, default: "receiving"
      t.datetime :expires_at, null: false
      t.datetime :received_at
      t.string :hint_kind, null: false, default: "purchase"
      t.string :hint_note
      t.string :batch_token
      t.integer :page_number
      t.integer :page_count
      t.string :refusal_reason
      t.bigint :document_id # the document of the inbox once accepted; written by the firm's side, no foreign key (the portal reads portal_* only)
      t.timestamps
    end
    add_index :portal_uploads, :token, unique: true
    add_index :portal_uploads, %i[portal_user_id sha256]
    add_index :portal_uploads, :batch_token

    create_table :portal_upload_chunks do |t|
      t.references :upload, null: false, foreign_key: { to_table: :portal_uploads }
      t.integer :position, null: false
      t.integer :byte_size, null: false
      t.string :sha256, null: false
      t.binary :content, null: false
      t.timestamps
    end
    add_index :portal_upload_chunks, %i[upload_id position], unique: true

    execute <<~SQL
      CREATE OR REPLACE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled,
               COALESCE((features ->> 'b02a')::boolean, false) AND COALESCE((features ->> 'b02b')::boolean, false) AND COALESCE((features ->> 'f03')::boolean, false) AS upload_enabled
        FROM entities
    SQL
  end

  def down
    execute <<~SQL
      DROP VIEW portal_companies;
      CREATE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled
        FROM entities
    SQL
    drop_table :portal_upload_chunks
    drop_table :portal_uploads
  end
end

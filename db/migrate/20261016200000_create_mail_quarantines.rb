# B02b: the mail to the documents address of a company is taken in only from the people of its portal and from addresses the firm lists, and only when the receiving server vouched for SPF and
# DKIM. What is not goes here, unread, for a person of the firm to look at. The portal shows the address of the company to those who may send documents (a column of the view).
class CreateMailQuarantines < ActiveRecord::Migration[8.1]
  def up
    add_column :entities, :documents_allowed_senders, :string, array: true, null: false, default: []

    create_table :accounting_mail_quarantines do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :sender
      t.string :subject
      t.string :message_id
      t.string :reason, null: false
      t.binary :raw, null: false
      t.integer :attachment_count, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :accounting_mail_quarantines, %i[entity_id status]

    execute <<~SQL
      CREATE OR REPLACE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled,
               COALESCE((features ->> 'b02a')::boolean, false) AND COALESCE((features ->> 'b02b')::boolean, false) AND COALESCE((features ->> 'f03')::boolean, false) AS upload_enabled,
               portal_show_bank_lines AS show_bank_lines, documents_mail_token
        FROM entities
    SQL
  end

  def down
    execute <<~SQL
      DROP VIEW portal_companies;
      CREATE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled,
               COALESCE((features ->> 'b02a')::boolean, false) AND COALESCE((features ->> 'b02b')::boolean, false) AND COALESCE((features ->> 'f03')::boolean, false) AS upload_enabled,
               portal_show_bank_lines AS show_bank_lines
        FROM entities
    SQL
    drop_table :accounting_mail_quarantines
    remove_column :entities, :documents_allowed_senders
  end
end

# F03: the secret part of the address that receives an entity's documents by e-mail (documents+<token>@<domain>).
# Existing entities get theirs here; a new one gets it on creation (has_secure_token).
class AddDocumentsMailTokenToEntities < ActiveRecord::Migration[8.1]
  def up
    add_column :entities, :documents_mail_token, :string
    execute("UPDATE entities SET documents_mail_token = replace(gen_random_uuid()::text, '-', '') WHERE documents_mail_token IS NULL")
    change_column_null :entities, :documents_mail_token, false
    add_index :entities, :documents_mail_token, unique: true
  end

  def down
    remove_column :entities, :documents_mail_token
  end
end

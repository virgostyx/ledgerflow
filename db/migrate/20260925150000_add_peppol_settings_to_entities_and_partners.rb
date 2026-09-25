class AddPeppolSettingsToEntitiesAndPartners < ActiveRecord::Migration[8.1]
  def up
    add_column :entities, :peppol_access_point, :integer # simulator: 0, digiteal: 1; NULL = Peppol not set up
    add_column :entities, :peppol_participant_id, :string
    add_column :entities, :peppol_credentials, :text     # encrypted JSON, keys declared by the access point adapter
    add_column :entities, :peppol_webhook_token, :string
    add_index  :entities, :peppol_participant_id, unique: true, where: "peppol_participant_id IS NOT NULL"
    add_index  :entities, :peppol_webhook_token, unique: true
    add_column :accounting_partners, :peppol_participant_id, :string

    # Existing entities need a webhook token too.
    execute("SELECT id FROM entities").each do |row|
      execute("UPDATE entities SET peppol_webhook_token = #{quote(SecureRandom.base58(24))} WHERE id = #{row['id']}")
    end
  end

  def down
    remove_column :accounting_partners, :peppol_participant_id
    remove_index  :entities, :peppol_webhook_token
    remove_index  :entities, :peppol_participant_id
    remove_column :entities, :peppol_webhook_token
    remove_column :entities, :peppol_credentials
    remove_column :entities, :peppol_participant_id
    remove_column :entities, :peppol_access_point
  end
end

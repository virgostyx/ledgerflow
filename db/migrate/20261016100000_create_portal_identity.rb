# B02a: the people from outside. A PortalUser is not a User: another table, another sign-in, no link between the two even for one person. Rights are only what
# portal_grants says (nothing by default). Every secret is stored as a digest or encrypted: the invitation token, the session token, the backup codes.
class CreatePortalIdentity < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_users do |t|
      t.string :email, null: false
      t.string :full_name, null: false
      t.string :locale, null: false, default: "en"
      t.string :status, null: false, default: "invited" # invited active suspended revoked
      t.string :password_digest
      t.text :totp_secret # encrypted
      t.datetime :totp_enabled_at
      t.bigint :totp_last_step
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_at
      t.datetime :last_sign_in_at
      t.datetime :last_seen_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :identity_verified_by, foreign_key: { to_table: :users }
      t.datetime :identity_verified_at
      t.timestamps
    end
    add_index :portal_users, "lower(email)", unique: true, name: "index_portal_users_on_lower_email"

    create_table :portal_backup_codes do |t|
      t.references :portal_user, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.datetime :used_at
      t.timestamps
    end

    create_table :portal_grants do |t|
      t.references :portal_user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :role, null: false # director collaborator reader
      t.jsonb :capabilities, null: false, default: []
      t.datetime :expires_at
      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users }
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :portal_grants, %i[portal_user_id entity_id], unique: true, where: "revoked_at IS NULL", name: "index_portal_grants_one_active_per_company"

    create_table :portal_invitations do |t|
      t.references :portal_user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :email, null: false
      t.string :role, null: false
      t.jsonb :capabilities, null: false, default: []
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :portal_invitations, :token_digest, unique: true

    create_table :portal_sessions do |t|
      t.references :portal_user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :ip_address
      t.string :user_agent
      t.datetime :last_seen_at, null: false
      t.datetime :second_factor_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :portal_sessions, :token_digest, unique: true
  end
end

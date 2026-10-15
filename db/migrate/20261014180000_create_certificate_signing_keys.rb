# B03c: the public keys of the Ed25519 keys that sign the certificates of this instance. The private keys are never here (nor in the repository, nor in the logs): they live in a
# directory outside the application, one file per key, named by `key_id`. A retired key stays forever so that old certificates can still be checked.
class CreateCertificateSigningKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :certificate_signing_keys do |t|
      t.string :key_id, null: false
      t.string :algorithm, null: false, default: "Ed25519"
      t.string :public_key, null: false # the 32 bytes of the public key, base64
      t.string :fingerprint, null: false, limit: 64 # SHA-256 of those bytes, hexadecimal
      t.string :status, null: false, default: "active"
      t.datetime :retired_at, precision: 6
      t.datetime :revoked_at, precision: 6
      t.string :revocation_reason
      t.timestamps
    end
    add_index :certificate_signing_keys, :key_id, unique: true
    add_index :certificate_signing_keys, :fingerprint, unique: true
    add_index :certificate_signing_keys, :status, unique: true, where: "status = 'active'", name: "index_signing_keys_one_active"
    add_check_constraint :certificate_signing_keys, "status IN ('active', 'retired', 'revoked')", name: "chk_signing_keys_status"
  end
end

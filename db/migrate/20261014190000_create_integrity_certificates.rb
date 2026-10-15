# B03c: the integrity certificates. What is signed is `body`, the canonical JSON (RFC 8785) of the certificate: it is stored as it was signed, so that it can be checked
# byte for byte; `payload` is the same thing as JSON for queries. A certificate is never changed; it can be revoked (for an error of issue), with a reason, once.
class CreateIntegrityCertificates < ActiveRecord::Migration[8.1]
  FUNCTION = <<~SQL.freeze
    CREATE FUNCTION protect_integrity_certificate() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'integrity certificates cannot be deleted' USING ERRCODE = 'raise_exception';
      END IF;
      IF (to_jsonb(NEW) - 'revoked_at' - 'revoked_by_id' - 'revocation_reason' - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'revoked_at' - 'revoked_by_id' - 'revocation_reason' - 'updated_at') THEN
        RAISE EXCEPTION 'integrity certificate % cannot be changed', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      IF OLD.revoked_at IS NOT NULL AND (NEW.revoked_at IS DISTINCT FROM OLD.revoked_at OR NEW.revocation_reason IS DISTINCT FROM OLD.revocation_reason) THEN
        RAISE EXCEPTION 'integrity certificate % is already revoked', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      RETURN NEW;
    END;
    $$;
  SQL

  def up
    create_table :integrity_certificates do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :uuid, null: false
      t.references :issued_by, null: false, foreign_key: { to_table: :users }
      t.references :fiscal_year, foreign_key: { to_table: :accounting_fiscal_years }
      t.datetime :covered_at, null: false, precision: 6
      t.bigint :through_seq, null: false
      t.integer :anchor_number, null: false
      t.string :disclosure_level, null: false
      t.string :recipient_label
      t.jsonb :payload, null: false
      t.text :body, null: false
      t.string :key_id, null: false
      t.text :signature, null: false
      t.datetime :revoked_at, precision: 6
      t.references :revoked_by, foreign_key: { to_table: :users }
      t.string :revocation_reason
      t.timestamps
    end
    add_index :integrity_certificates, :uuid, unique: true
    add_check_constraint :integrity_certificates, "disclosure_level IN ('minimal', 'standard', 'full')", name: "chk_certificates_level"
    add_check_constraint :integrity_certificates, "(revoked_at IS NULL) = (revocation_reason IS NULL)", name: "chk_certificates_revocation"
    execute FUNCTION
    execute "CREATE TRIGGER protect_integrity_certificate BEFORE UPDATE OR DELETE ON integrity_certificates FOR EACH ROW EXECUTE FUNCTION protect_integrity_certificate()"
  end

  def down
    execute "DROP TRIGGER protect_integrity_certificate ON integrity_certificates"
    execute "DROP FUNCTION protect_integrity_certificate()"
    drop_table :integrity_certificates
  end
end

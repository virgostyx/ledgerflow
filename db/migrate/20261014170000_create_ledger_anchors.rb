# B03c: the anchors. An anchor binds, at an instant, the fingerprints of the entries validated since the previous anchor (a Merkle root, over `content_hash` in the order of
# `posted_seq`), the head of the audit chain, and the previous anchor: a chain that nothing can be removed from or put back in without breaking it.
#
# An anchor is never changed. The one thing that may still be written is the external timestamp (RFC 3161) of its fingerprint, once: the authority may answer later.
class CreateLedgerAnchors < ActiveRecord::Migration[8.1]
  FUNCTION = <<~SQL.freeze
    CREATE FUNCTION protect_ledger_anchor() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'ledger anchors cannot be deleted' USING ERRCODE = 'raise_exception';
      END IF;
      IF (to_jsonb(NEW) - 'timestamp_token' - 'timestamp_authority' - 'timestamped_at' - 'timestamp_error' - 'updated_at')
         IS DISTINCT FROM (to_jsonb(OLD) - 'timestamp_token' - 'timestamp_authority' - 'timestamped_at' - 'timestamp_error' - 'updated_at') THEN
        RAISE EXCEPTION 'ledger anchor % cannot be changed', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      IF OLD.timestamp_token IS NOT NULL AND NEW.timestamp_token IS DISTINCT FROM OLD.timestamp_token THEN
        RAISE EXCEPTION 'the timestamp of ledger anchor % cannot change', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      RETURN NEW;
    END;
    $$;
  SQL

  def up
    create_table :ledger_anchors do |t|
      t.references :entity, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :kind, null: false
      t.bigint :from_seq, null: false
      t.bigint :to_seq, null: false
      t.integer :entries_count, null: false
      t.integer :retroactive_entries, null: false, default: 0
      t.string :merkle_root, null: false, limit: 64
      t.string :audit_head, limit: 64
      t.bigint :audit_length, null: false, default: 0
      t.string :previous_anchor_hash, limit: 64
      t.string :anchor_hash, null: false, limit: 64
      t.datetime :anchored_at, null: false, precision: 6
      t.text :timestamp_token
      t.string :timestamp_authority
      t.datetime :timestamped_at, precision: 6
      t.string :timestamp_error
      t.timestamps
    end
    add_index :ledger_anchors, %i[entity_id number], unique: true
    add_index :ledger_anchors, %i[entity_id to_seq]
    add_check_constraint :ledger_anchors, "kind IN ('nightly', 'on_demand', 'retroactive')", name: "chk_ledger_anchors_kind"
    add_check_constraint :ledger_anchors, "merkle_root ~ '^[0-9a-f]{64}$' AND anchor_hash ~ '^[0-9a-f]{64}$'", name: "chk_ledger_anchors_hex"
    add_check_constraint :ledger_anchors, "to_seq >= from_seq - 1 AND entries_count >= 0", name: "chk_ledger_anchors_range"
    execute FUNCTION
    execute "CREATE TRIGGER protect_ledger_anchor BEFORE UPDATE OR DELETE ON ledger_anchors FOR EACH ROW EXECUTE FUNCTION protect_ledger_anchor()"
  end

  def down
    execute "DROP TRIGGER protect_ledger_anchor ON ledger_anchors"
    execute "DROP FUNCTION protect_ledger_anchor()"
    drop_table :ledger_anchors
  end
end

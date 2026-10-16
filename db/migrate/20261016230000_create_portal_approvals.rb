# B02c: the client's validation of the accounts. A publication may ask for approval (`requires_approval`): who may give it is listed (approvers, directors whose identity the firm checked), how many
# are needed (one or all), and what each one opened is kept (views). A decision is a proof: the publication and the fingerprint of the manifest of its files, who, when, from where, how the second
# factor was given, and the text shown to them, hashed in canonical JSON (evidence_hash). The proof is immutable: only the seal that the firm's side puts on it (the signature) and its being
# superseded by a newer version of the publication can be written, once each.
class CreatePortalApprovals < ActiveRecord::Migration[8.1]
  def up
    add_column :portal_publications, :approvals_required, :string, null: false, default: "one" # "one" or "all" of the approvers
    add_column :portal_sessions, :second_factor_method, :string
    add_column :entities, :client_approval_required, :boolean, null: false, default: false

    create_table :portal_publication_approvers do |t|
      t.references :publication, null: false, foreign_key: { to_table: :portal_publications }
      t.references :portal_user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :portal_publication_approvers, %i[publication_id portal_user_id], unique: true, name: "index_portal_approvers_unique"
    execute "CREATE TRIGGER protect_portal_publication_approvers BEFORE UPDATE OR DELETE ON portal_publication_approvers FOR EACH ROW EXECUTE FUNCTION protect_portal_publication_part()"

    create_table :portal_document_views do |t|
      t.references :publication_file, null: false, foreign_key: { to_table: :portal_publication_files }
      t.references :portal_user, null: false, foreign_key: true
      t.datetime :viewed_at, null: false
      t.timestamps
    end
    add_index :portal_document_views, %i[publication_file_id portal_user_id], unique: true, name: "index_portal_views_unique"

    create_table :portal_approvals do |t|
      t.references :publication, null: false, foreign_key: { to_table: :portal_publications }
      t.references :portal_user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :decision, null: false # approved, approved_with_remarks, refused
      t.text :comment
      t.string :manifest_hash, null: false
      t.jsonb :evidence, null: false
      t.string :evidence_hash, null: false
      t.string :status, null: false, default: "active" # active, superseded
      t.string :seal_key_id
      t.text :seal_signature
      t.datetime :sealed_at
      t.timestamps
    end
    add_index :portal_approvals, %i[publication_id portal_user_id], where: "status = 'active'", unique: true, name: "index_portal_approvals_one_active"

    execute <<~SQL
      CREATE FUNCTION protect_portal_approval() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'a client approval cannot be deleted' USING ERRCODE = 'raise_exception';
        END IF;
        IF (to_jsonb(NEW) - 'status' - 'seal_key_id' - 'seal_signature' - 'sealed_at' - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'status' - 'seal_key_id' - 'seal_signature' - 'sealed_at' - 'updated_at') THEN
          RAISE EXCEPTION 'client approval % cannot be changed', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.sealed_at IS NOT NULL AND (NEW.seal_key_id IS DISTINCT FROM OLD.seal_key_id OR NEW.seal_signature IS DISTINCT FROM OLD.seal_signature OR NEW.sealed_at IS DISTINCT FROM OLD.sealed_at) THEN
          RAISE EXCEPTION 'client approval % is already sealed', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.status = 'superseded' AND NEW.status <> 'superseded' THEN
          RAISE EXCEPTION 'client approval % is superseded for good', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER protect_portal_approval BEFORE UPDATE OR DELETE ON portal_approvals FOR EACH ROW EXECUTE FUNCTION protect_portal_approval();
    SQL
  end

  def down
    execute "DROP TRIGGER protect_portal_approval ON portal_approvals; DROP FUNCTION protect_portal_approval()"
    drop_table :portal_approvals
    drop_table :portal_document_views
    execute "DROP TRIGGER protect_portal_publication_approvers ON portal_publication_approvers"
    drop_table :portal_publication_approvers
    remove_column :entities, :client_approval_required
    remove_column :portal_sessions, :second_factor_method
    remove_column :portal_publications, :approvals_required
  end
end

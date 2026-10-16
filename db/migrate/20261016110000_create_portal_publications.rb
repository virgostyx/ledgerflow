# B02a: what the firm publishes to the portal. A publication is frozen: its files (the content itself is kept here, so that the portal reads portal_* only and a database role
# limited to them is enough) and their SHA-256. Correcting is a new version; withdrawing hides it. Only the marks of replacement and withdrawal can change, once.
class CreatePortalPublications < ActiveRecord::Migration[8.1]
  def up
    create_table :portal_publications do |t|
      t.string :token, null: false
      t.references :entity, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :title, null: false
      t.date :period_start
      t.date :period_end
      t.text :message
      t.references :published_by, null: false, foreign_key: { to_table: :users }
      t.datetime :published_at, null: false
      t.integer :version, null: false, default: 1
      t.references :replaces, foreign_key: { to_table: :portal_publications }
      t.references :replaced_by, foreign_key: { to_table: :portal_publications }
      t.boolean :requires_approval, null: false, default: false
      t.boolean :watermark, null: false, default: true
      t.datetime :expires_at
      t.datetime :known_at
      t.string :status, null: false, default: "published"
      t.datetime :withdrawn_at
      t.references :withdrawn_by, foreign_key: { to_table: :users }
      t.text :withdrawal_reason
      t.timestamps
    end
    add_index :portal_publications, :token, unique: true

    create_table :portal_publication_files do |t|
      t.references :publication, null: false, foreign_key: { to_table: :portal_publications }
      t.string :token, null: false
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :sha256, null: false
      t.binary :content, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :portal_publication_files, :token, unique: true

    create_table :portal_publication_recipients do |t|
      t.references :publication, null: false, foreign_key: { to_table: :portal_publications }
      t.references :portal_user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :portal_publication_recipients, %i[publication_id portal_user_id], unique: true, name: "index_portal_recipients_unique"

    execute <<~SQL
      CREATE FUNCTION protect_portal_publication() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'a portal publication cannot be deleted' USING ERRCODE = 'raise_exception';
        END IF;
        IF (to_jsonb(NEW) - 'replaced_by_id' - 'status' - 'withdrawn_at' - 'withdrawn_by_id' - 'withdrawal_reason' - 'updated_at')
           IS DISTINCT FROM (to_jsonb(OLD) - 'replaced_by_id' - 'status' - 'withdrawn_at' - 'withdrawn_by_id' - 'withdrawal_reason' - 'updated_at') THEN
          RAISE EXCEPTION 'portal publication % cannot be changed', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.replaced_by_id IS NOT NULL AND NEW.replaced_by_id IS DISTINCT FROM OLD.replaced_by_id THEN
          RAISE EXCEPTION 'portal publication % is already replaced', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.status = 'withdrawn' AND (NEW.status <> 'withdrawn' OR NEW.withdrawn_at IS DISTINCT FROM OLD.withdrawn_at OR NEW.withdrawal_reason IS DISTINCT FROM OLD.withdrawal_reason) THEN
          RAISE EXCEPTION 'portal publication % is already withdrawn', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER protect_portal_publication BEFORE UPDATE OR DELETE ON portal_publications FOR EACH ROW EXECUTE FUNCTION protect_portal_publication();

      CREATE FUNCTION protect_portal_publication_part() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION '% of a portal publication cannot be changed or deleted', TG_TABLE_NAME USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER protect_portal_publication_files BEFORE UPDATE OR DELETE ON portal_publication_files FOR EACH ROW EXECUTE FUNCTION protect_portal_publication_part();
      CREATE TRIGGER protect_portal_publication_recipients BEFORE UPDATE OR DELETE ON portal_publication_recipients FOR EACH ROW EXECUTE FUNCTION protect_portal_publication_part();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER protect_portal_publication_recipients ON portal_publication_recipients;
      DROP TRIGGER protect_portal_publication_files ON portal_publication_files;
      DROP TRIGGER protect_portal_publication ON portal_publications;
      DROP FUNCTION protect_portal_publication_part();
      DROP FUNCTION protect_portal_publication();
    SQL
    drop_table :portal_publication_recipients
    drop_table :portal_publication_files
    drop_table :portal_publications
  end
end

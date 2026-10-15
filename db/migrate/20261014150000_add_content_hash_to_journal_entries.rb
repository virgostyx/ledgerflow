# B03c: the fingerprint of the content of a validated entry (`content_hash`: SHA-256 of its canonical form, see Ledger::EntryContent), who validated it (`posted_by_id`, part
# of what is fingerprinted), and where the fingerprint comes from (`live`: written when the entry was validated; `retroactive`: written afterwards, for what was validated before
# the fingerprints existed).
#
# The database lets the fingerprint be written once, on an entry that has its place (`posted_seq`), and never changed or removed; the author of the validation is fixed with the
# place. An entry validated and not yet fingerprinted is the only thing that can still get one.
class AddContentHashToJournalEntries < ActiveRecord::Migration[8.1]
  FUNCTION = <<~SQL.freeze
    CREATE FUNCTION protect_entry_content_hash() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    BEGIN
      IF OLD.content_hash IS NOT NULL AND (NEW.content_hash IS DISTINCT FROM OLD.content_hash OR NEW.content_hash_source IS DISTINCT FROM OLD.content_hash_source) THEN
        RAISE EXCEPTION 'the content_hash of entry % cannot change', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      IF OLD.content_hash IS NULL AND NEW.content_hash IS NOT NULL AND NEW.posted_seq IS NULL THEN
        RAISE EXCEPTION 'entry % is not validated: it has no content_hash', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      IF OLD.posted_seq IS NOT NULL AND NEW.posted_by_id IS DISTINCT FROM OLD.posted_by_id THEN
        RAISE EXCEPTION 'the author of the validation of entry % cannot change (posted_by_id)', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      RETURN NEW;
    END;
    $$;
  SQL

  def up
    change_table :accounting_journal_entries, bulk: true do |t|
      t.string :content_hash, limit: 64
      t.string :content_hash_source
      t.bigint :posted_by_id
    end
    add_foreign_key :accounting_journal_entries, :users, column: :posted_by_id
    add_check_constraint :accounting_journal_entries, "content_hash IS NULL OR content_hash ~ '^[0-9a-f]{64}$'", name: "chk_entries_content_hash_hex"
    add_check_constraint :accounting_journal_entries, "(content_hash IS NULL) = (content_hash_source IS NULL)", name: "chk_entries_content_hash_source"
    add_check_constraint :accounting_journal_entries, "content_hash_source IS NULL OR content_hash_source IN ('live', 'retroactive')", name: "chk_entries_content_hash_source_values"
    add_index :accounting_journal_entries, %i[entity_id posted_seq], where: "content_hash IS NULL AND posted_seq IS NOT NULL", name: "index_entries_not_yet_fingerprinted"
    execute FUNCTION
    execute "CREATE TRIGGER protect_entry_content_hash BEFORE UPDATE ON accounting_journal_entries FOR EACH ROW EXECUTE FUNCTION protect_entry_content_hash()"
  end

  def down
    execute "DROP TRIGGER protect_entry_content_hash ON accounting_journal_entries"
    execute "DROP FUNCTION protect_entry_content_hash()"
    remove_index :accounting_journal_entries, name: "index_entries_not_yet_fingerprinted"
    remove_check_constraint :accounting_journal_entries, name: "chk_entries_content_hash_source_values"
    remove_check_constraint :accounting_journal_entries, name: "chk_entries_content_hash_source"
    remove_check_constraint :accounting_journal_entries, name: "chk_entries_content_hash_hex"
    remove_foreign_key :accounting_journal_entries, column: :posted_by_id
    change_table :accounting_journal_entries, bulk: true do |t|
      t.remove :content_hash, :content_hash_source, :posted_by_id
    end
  end
end

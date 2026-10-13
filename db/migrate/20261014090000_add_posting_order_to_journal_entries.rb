# B03a: the instant a journal entry was validated (`posted_at`) and its place in the order of the company (`posted_seq`), both fixed by the database and never changed, so that
# the books can be shown "as they were known" at any instant. The trigger takes a lock per company until the end of the transaction: places are given in the order the
# transactions commit, and no instant goes backwards.
#
# The entries already validated get a place too, ordered by the instant they were locked (else last changed), marked `backfill`: it is the best the database knows.
class AddPostingOrderToJournalEntries < ActiveRecord::Migration[8.1]
  FUNCTION = <<~SQL.freeze
    CREATE FUNCTION assign_entry_posting() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    DECLARE
      v_last_seq bigint;
      v_last_at timestamp;
      v_stamp timestamp;
      v_setting text;
    BEGIN
      IF TG_OP = 'UPDATE' AND OLD.posted_seq IS NOT NULL THEN
        IF NEW.posted_at IS DISTINCT FROM OLD.posted_at OR NEW.posted_seq IS DISTINCT FROM OLD.posted_seq OR NEW.posted_at_source IS DISTINCT FROM OLD.posted_at_source THEN
          RAISE EXCEPTION 'the instant and the place of the validated entry % cannot change (posted_at, posted_seq)', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.status = 0 THEN
          RAISE EXCEPTION 'the validated entry % cannot go back to a draft (posted_at)', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END IF;

      IF NEW.status = 0 THEN
        IF NEW.posted_at IS NOT NULL OR NEW.posted_seq IS NOT NULL OR NEW.posted_at_source IS NOT NULL THEN
          RAISE EXCEPTION 'a draft has no posted_at' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END IF;

      -- the entry becomes validated now (or is written validated): its place is the next one of the company, its instant is the clock of the database
      PERFORM pg_advisory_xact_lock(hashtext('entry_posting'), NEW.entity_id::integer);
      SELECT posted_seq, posted_at INTO v_last_seq, v_last_at
        FROM accounting_journal_entries WHERE entity_id = NEW.entity_id AND posted_seq IS NOT NULL ORDER BY posted_seq DESC LIMIT 1;

      -- one instant for what one transaction validates (txid|instant): a view at an instant shows all of it or none of it
      v_setting := current_setting('ledgerflow.posted_at', true);
      IF v_setting IS NOT NULL AND v_setting LIKE txid_current()::text || '|%' THEN
        v_stamp := split_part(v_setting, '|', 2)::timestamp;
      ELSE
        v_stamp := clock_timestamp() AT TIME ZONE 'UTC';
        PERFORM set_config('ledgerflow.posted_at', txid_current()::text || '|' || v_stamp::text, true);
      END IF;

      NEW.posted_seq := COALESCE(v_last_seq, 0) + 1;
      NEW.posted_at := GREATEST(v_stamp, COALESCE(v_last_at, v_stamp));
      NEW.posted_at_source := CASE WHEN NEW.import_batch_id IS NOT NULL THEN 'import' ELSE 'live' END;
      RETURN NEW;
    END;
    $$;
  SQL

  VIEW_WITH_ORDER = <<~SQL.freeze
    CREATE VIEW posted_lines AS
     SELECT l.id, l.entity_id, e.id AS journal_entry_id, e.fiscal_year_id, e.journal_id, e.entry_date, e.reference, l.account_id, l.partner_id, l.debit, l.credit, l.label,
            l.vat_code, l.lettering_id, l.currency, l.amount_currency, e.posted_seq, e.posted_at
       FROM (accounting_journal_entry_lines l JOIN accounting_journal_entries e ON ((e.id = l.journal_entry_id)))
      WHERE (e.status = ANY (ARRAY[1, 2]))
  SQL

  VIEW_BEFORE = <<~SQL.freeze
    CREATE VIEW posted_lines AS
     SELECT l.id, l.entity_id, e.id AS journal_entry_id, e.fiscal_year_id, e.journal_id, e.entry_date, e.reference, l.account_id, l.partner_id, l.debit, l.credit, l.label,
            l.vat_code, l.lettering_id, l.currency, l.amount_currency
       FROM (accounting_journal_entry_lines l JOIN accounting_journal_entries e ON ((e.id = l.journal_entry_id)))
      WHERE (e.status = ANY (ARRAY[1, 2]))
  SQL

  def up
    change_table :accounting_journal_entries, bulk: true do |t|
      t.datetime :posted_at, precision: 6
      t.bigint :posted_seq
      t.string :posted_at_source
    end

    execute "SET LOCAL ledgerflow.lock_override = 'on'" # the entries of a locked period get their place too: nothing else changes
    execute <<~SQL
      UPDATE accounting_journal_entries e
         SET posted_at = s.at, posted_seq = s.rn, posted_at_source = 'backfill'
        FROM (SELECT id, COALESCE(locked_at, updated_at) AS at,
                     ROW_NUMBER() OVER (PARTITION BY entity_id ORDER BY COALESCE(locked_at, updated_at), id) AS rn
                FROM accounting_journal_entries WHERE status <> 0) s
       WHERE e.id = s.id
    SQL
    execute "SET LOCAL ledgerflow.lock_override = 'off'"

    add_index :accounting_journal_entries, %i[entity_id posted_seq], unique: true, where: "posted_seq IS NOT NULL", name: "index_entries_on_entity_and_posted_seq"
    execute FUNCTION
    execute "CREATE TRIGGER assign_entry_posting BEFORE INSERT OR UPDATE ON accounting_journal_entries FOR EACH ROW EXECUTE FUNCTION assign_entry_posting()"
    execute "DROP VIEW posted_lines"
    execute VIEW_WITH_ORDER
  end

  def down
    execute "DROP VIEW posted_lines"
    execute VIEW_BEFORE
    execute "DROP TRIGGER assign_entry_posting ON accounting_journal_entries"
    execute "DROP FUNCTION assign_entry_posting()"
    remove_index :accounting_journal_entries, name: "index_entries_on_entity_and_posted_seq"
    change_table :accounting_journal_entries, bulk: true do |t|
      t.remove :posted_at, :posted_seq, :posted_at_source
    end
  end
end

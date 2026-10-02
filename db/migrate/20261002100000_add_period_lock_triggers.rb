# F01, second layer of the period lock: PostgreSQL refuses to insert, change or delete the validated entries
# (and their lines) of a locked period, whatever the application does. Lettering stays possible: a line may
# still change lettering_id / amount_residual. A controlled window (migration, closing) sets the session
# variable ledgerflow.lock_override = 'on' for the length of its transaction.
class AddPeriodLockTriggers < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION entry_in_locked_period(p_entry_id bigint) RETURNS boolean AS $$
        SELECT EXISTS (
          SELECT 1
          FROM accounting_journal_entries e
          JOIN accounting_period_locks l ON l.entity_id = e.entity_id AND l.status = 0
                                        AND e.entry_date BETWEEN l.starts_on AND l.ends_on
          WHERE e.id = p_entry_id AND e.status <> 0
        )
      $$ LANGUAGE sql STABLE;

      CREATE FUNCTION date_in_locked_period(p_entity_id bigint, p_date date) RETURNS boolean AS $$
        SELECT EXISTS (
          SELECT 1 FROM accounting_period_locks l
          WHERE l.entity_id = p_entity_id AND l.status = 0 AND p_date BETWEEN l.starts_on AND l.ends_on
        )
      $$ LANGUAGE sql STABLE;

      CREATE FUNCTION enforce_period_lock_on_entries() RETURNS trigger AS $$
      BEGIN
        IF current_setting('ledgerflow.lock_override', true) = 'on' THEN
          RETURN COALESCE(NEW, OLD);
        END IF;
        IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.status <> 0 AND date_in_locked_period(OLD.entity_id, OLD.entry_date) THEN
          RAISE EXCEPTION 'entry % is validated and inside a locked period', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.status <> 0 AND date_in_locked_period(NEW.entity_id, NEW.entry_date) THEN
          RAISE EXCEPTION 'entry % cannot be validated inside a locked period', NEW.id USING ERRCODE = 'raise_exception';
        END IF;
        RETURN COALESCE(NEW, OLD);
      END;
      $$ LANGUAGE plpgsql;

      CREATE FUNCTION enforce_period_lock_on_lines() RETURNS trigger AS $$
      BEGIN
        IF current_setting('ledgerflow.lock_override', true) = 'on' THEN
          RETURN COALESCE(NEW, OLD);
        END IF;
        -- lettering stays possible in a locked period: only these columns may change
        IF TG_OP = 'UPDATE' AND NEW.journal_entry_id = OLD.journal_entry_id
           AND (to_jsonb(NEW) - ARRAY['lettering_id', 'amount_residual', 'updated_at'])
             = (to_jsonb(OLD) - ARRAY['lettering_id', 'amount_residual', 'updated_at']) THEN
          RETURN NEW;
        END IF;
        IF TG_OP IN ('UPDATE', 'DELETE') AND entry_in_locked_period(OLD.journal_entry_id) THEN
          RAISE EXCEPTION 'line % belongs to a validated entry of a locked period', OLD.id USING ERRCODE = 'raise_exception';
        END IF;
        IF TG_OP IN ('INSERT', 'UPDATE') AND entry_in_locked_period(NEW.journal_entry_id) THEN
          RAISE EXCEPTION 'a line cannot be added to a validated entry of a locked period' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN COALESCE(NEW, OLD);
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER enforce_period_lock_entries BEFORE INSERT OR UPDATE OR DELETE ON accounting_journal_entries
        FOR EACH ROW EXECUTE FUNCTION enforce_period_lock_on_entries();
      CREATE TRIGGER enforce_period_lock_lines BEFORE INSERT OR UPDATE OR DELETE ON accounting_journal_entry_lines
        FOR EACH ROW EXECUTE FUNCTION enforce_period_lock_on_lines();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER enforce_period_lock_lines ON accounting_journal_entry_lines;
      DROP TRIGGER enforce_period_lock_entries ON accounting_journal_entries;
      DROP FUNCTION enforce_period_lock_on_lines();
      DROP FUNCTION enforce_period_lock_on_entries();
      DROP FUNCTION date_in_locked_period(bigint, date);
      DROP FUNCTION entry_in_locked_period(bigint);
    SQL
  end
end

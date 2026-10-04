# F07: reversing an entry of a locked period is done by a new entry (dated in an open period); flagging the original as reversed changes
# no amount, so the lock lets that one change through (as it does for lettering): status posted -> reversed, nothing else.
class AllowReversedFlagInLockedPeriod < ActiveRecord::Migration[8.1]
  FUNCTION = <<~SQL.freeze
    CREATE OR REPLACE FUNCTION enforce_period_lock_on_entries() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    BEGIN
      IF current_setting('ledgerflow.lock_override', true) = 'on' THEN
        RETURN COALESCE(NEW, OLD);
      END IF;
      %<reversed_flag>s
      IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.status <> 0 AND date_in_locked_period(OLD.entity_id, OLD.entry_date) THEN
        RAISE EXCEPTION 'entry %% is validated and inside a locked period', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.status <> 0 AND date_in_locked_period(NEW.entity_id, NEW.entry_date) THEN
        RAISE EXCEPTION 'entry %% cannot be validated inside a locked period', NEW.id USING ERRCODE = 'raise_exception';
      END IF;
      RETURN COALESCE(NEW, OLD);
    END;
    $$;
  SQL

  FLAG = <<~SQL.strip.freeze
    IF TG_OP = 'UPDATE' AND OLD.status = 1 AND NEW.status = 2
       AND (to_jsonb(NEW) - 'status' - 'updated_at') = (to_jsonb(OLD) - 'status' - 'updated_at') THEN
        RETURN NEW;
      END IF;
  SQL

  def up
    execute format(FUNCTION, reversed_flag: FLAG)
  end

  def down
    execute format(FUNCTION, reversed_flag: "")
  end
end

# B03a: what the books said of a lettering at an instant. The history of a line (lettered, unlettered) now carries the date of the lettering and the clock of the database;
# the partial settlements, which are deleted when undone, leave a version behind (a trigger, so nothing can skip it). Both are what a past residual is rebuilt from.
class DateLetteringHistory < ActiveRecord::Migration[8.1]
  EVENT_FUNCTION = <<~SQL.freeze
    CREATE FUNCTION date_lettering_event() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    BEGIN
      NEW.created_at := clock_timestamp() AT TIME ZONE 'UTC';
      RETURN NEW;
    END;
    $$;
  SQL

  VERSION_FUNCTION = <<~SQL.freeze
    CREATE FUNCTION record_allocation_version() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    BEGIN
      IF TG_OP IN ('UPDATE', 'DELETE') THEN
        INSERT INTO accounting_allocation_versions (entity_id, allocation_id, debit_line_id, credit_line_id, amount, allocated_on, action, at)
        VALUES (OLD.entity_id, OLD.id, OLD.debit_line_id, OLD.credit_line_id, OLD.amount, OLD.allocated_on, 'remove', clock_timestamp() AT TIME ZONE 'UTC');
      END IF;
      IF TG_OP IN ('INSERT', 'UPDATE') THEN
        INSERT INTO accounting_allocation_versions (entity_id, allocation_id, debit_line_id, credit_line_id, amount, allocated_on, action, at)
        VALUES (NEW.entity_id, NEW.id, NEW.debit_line_id, NEW.credit_line_id, NEW.amount, NEW.allocated_on, 'add', clock_timestamp() AT TIME ZONE 'UTC');
      END IF;
      RETURN COALESCE(NEW, OLD);
    END;
    $$;
  SQL

  IMMUTABLE_FUNCTION = <<~SQL.freeze
    CREATE FUNCTION prevent_allocation_version_change() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    BEGIN
      RAISE EXCEPTION 'the history of the allocations is never changed' USING ERRCODE = 'raise_exception';
    END;
    $$;
  SQL

  def up
    add_column :accounting_lettering_events, :lettered_on, :date
    execute <<~SQL
      UPDATE accounting_lettering_events ev
         SET lettered_on = COALESCE((SELECT lt.lettered_on FROM accounting_letterings lt WHERE lt.entity_id = ev.entity_id AND lt.code = ev.code LIMIT 1), ev.created_at::date)
    SQL
    execute EVENT_FUNCTION
    execute "CREATE TRIGGER date_lettering_event BEFORE INSERT ON accounting_lettering_events FOR EACH ROW EXECUTE FUNCTION date_lettering_event()"

    create_table :accounting_allocation_versions do |t|
      t.bigint :entity_id, null: false
      t.bigint :allocation_id, null: false
      t.bigint :debit_line_id, null: false
      t.bigint :credit_line_id, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.date :allocated_on, null: false
      t.string :action, null: false
      t.datetime :at, null: false, precision: 6
    end
    add_index :accounting_allocation_versions, :debit_line_id
    add_index :accounting_allocation_versions, :credit_line_id
    add_index :accounting_allocation_versions, :allocation_id
    add_index :accounting_lettering_events, %i[line_id created_at], name: "index_lettering_events_on_line_and_instant"

    execute <<~SQL
      INSERT INTO accounting_allocation_versions (entity_id, allocation_id, debit_line_id, credit_line_id, amount, allocated_on, action, at)
      SELECT entity_id, id, debit_line_id, credit_line_id, amount, allocated_on, 'add', created_at FROM accounting_line_allocations
    SQL
    execute VERSION_FUNCTION
    execute "CREATE TRIGGER record_allocation_version AFTER INSERT OR UPDATE OR DELETE ON accounting_line_allocations FOR EACH ROW EXECUTE FUNCTION record_allocation_version()"
    execute IMMUTABLE_FUNCTION
    execute "CREATE TRIGGER prevent_allocation_version_change BEFORE UPDATE OR DELETE ON accounting_allocation_versions FOR EACH ROW EXECUTE FUNCTION prevent_allocation_version_change()"
  end

  def down
    execute "DROP TRIGGER prevent_allocation_version_change ON accounting_allocation_versions"
    execute "DROP FUNCTION prevent_allocation_version_change()"
    execute "DROP TRIGGER record_allocation_version ON accounting_line_allocations"
    execute "DROP FUNCTION record_allocation_version()"
    remove_index :accounting_lettering_events, name: "index_lettering_events_on_line_and_instant"
    drop_table :accounting_allocation_versions
    execute "DROP TRIGGER date_lettering_event ON accounting_lettering_events"
    execute "DROP FUNCTION date_lettering_event()"
    remove_column :accounting_lettering_events, :lettered_on
  end
end

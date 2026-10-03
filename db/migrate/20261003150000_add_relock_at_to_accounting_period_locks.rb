# F01: a temporary unlock. While relock_at is in the future the period is open; from that moment PostgreSQL counts it as
# locked again, whether or not the job that flips the status has run yet.
class AddRelockAtToAccountingPeriodLocks < ActiveRecord::Migration[8.1]
  LOCKED = "(l.status = 0 OR (l.relock_at IS NOT NULL AND l.relock_at <= now()))".freeze
  PREVIOUS = "l.status = 0".freeze

  def up
    add_column :accounting_period_locks, :relock_at, :datetime
    redefine(LOCKED)
  end

  def down
    redefine(PREVIOUS)
    remove_column :accounting_period_locks, :relock_at
  end

  private

  def redefine(condition)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION entry_in_locked_period(p_entry_id bigint) RETURNS boolean AS $$
        SELECT EXISTS (
          SELECT 1
          FROM accounting_journal_entries e
          JOIN accounting_period_locks l ON l.entity_id = e.entity_id AND #{condition}
                                        AND e.entry_date BETWEEN l.starts_on AND l.ends_on
          WHERE e.id = p_entry_id AND e.status <> 0
        )
      $$ LANGUAGE sql STABLE;

      CREATE OR REPLACE FUNCTION date_in_locked_period(p_entity_id bigint, p_date date) RETURNS boolean AS $$
        SELECT EXISTS (
          SELECT 1 FROM accounting_period_locks l
          WHERE l.entity_id = p_entity_id AND #{condition} AND p_date BETWEEN l.starts_on AND l.ends_on
        )
      $$ LANGUAGE sql STABLE;
    SQL
  end
end

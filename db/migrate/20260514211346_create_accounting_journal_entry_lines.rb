class CreateAccountingJournalEntryLines < ActiveRecord::Migration[8.1]
  def up
    create_table :accounting_journal_entry_lines do |t|
      t.references :journal_entry, null: false,
                   foreign_key:    { to_table: :accounting_journal_entries }
      t.references :account,       null: false,
                   foreign_key:    { to_table: :accounting_accounts }
      t.bigint  :partner_id  # FK added in Phase 7 when accounting_partners exists

      t.decimal :debit,    precision: 15, scale: 2, null: false, default: 0
      t.decimal :credit,   precision: 15, scale: 2, null: false, default: 0

      t.string  :label
      t.integer :vat_code
      t.decimal :vat_amount,       precision: 15, scale: 2
      t.string  :currency,         null: false, default: 'EUR'
      t.decimal :amount_currency,  precision: 15, scale: 2
      t.decimal :exchange_rate,    precision: 10, scale: 6
      t.integer :sort_order,       null: false, default: 0

      t.timestamps
    end

    add_index :accounting_journal_entry_lines, :partner_id

    # Contraintes CHECK PostgreSQL
    execute <<~SQL
      ALTER TABLE accounting_journal_entry_lines
        ADD CONSTRAINT chk_debit_non_negative  CHECK (debit  >= 0),
        ADD CONSTRAINT chk_credit_non_negative CHECK (credit >= 0),
        ADD CONSTRAINT chk_not_both_sides      CHECK (NOT (debit > 0 AND credit > 0)),
        ADD CONSTRAINT chk_at_least_one_side   CHECK (debit > 0 OR credit > 0);
    SQL

    # Trigger partie double — DEFERRABLE pour permettre l insertion de lignes
    # multiples dans une transaction (SET CONSTRAINTS enforce_double_entry DEFERRED)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION enforce_double_entry_check()
      RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE
        v_debit  NUMERIC;
        v_credit NUMERIC;
      BEGIN
        SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
          INTO v_debit, v_credit
          FROM accounting_journal_entry_lines
         WHERE journal_entry_id = NEW.journal_entry_id;

        IF ABS(v_debit - v_credit) > 0.005 THEN
          RAISE EXCEPTION 'Unbalanced entry (journal_entry_id=%): debit=% credit=%',
            NEW.journal_entry_id, v_debit, v_credit;
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE CONSTRAINT TRIGGER enforce_double_entry
      AFTER INSERT OR UPDATE ON accounting_journal_entry_lines
      DEFERRABLE INITIALLY IMMEDIATE
      FOR EACH ROW EXECUTE FUNCTION enforce_double_entry_check();
    SQL
  end

  def down
    execute "DROP TRIGGER  IF EXISTS enforce_double_entry ON accounting_journal_entry_lines;"
    execute "DROP FUNCTION IF EXISTS enforce_double_entry_check();"
    drop_table :accounting_journal_entry_lines
  end
end

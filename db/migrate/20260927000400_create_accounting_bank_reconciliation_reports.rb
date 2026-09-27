class CreateAccountingBankReconciliationReports < ActiveRecord::Migration[8.1]
  # docs/dev/reports/spec.md §8: "figer" a bank reconciliation (R06) — the
  # full result, a content hash, who ran it, when. Immutable once created,
  # same trigger pattern as accounting_audit_logs (db/migrate/20260514185027).
  def up
    create_table :accounting_bank_reconciliation_reports do |t|
      t.bigint  :entity_id,      null: false
      t.bigint  :bank_account_id, null: false
      t.date    :as_of,          null: false
      t.jsonb   :result,         null: false, default: {}
      t.string  :content_hash,   null: false
      t.bigint  :user_id
      t.timestamps
    end

    add_index :accounting_bank_reconciliation_reports, :entity_id
    add_index :accounting_bank_reconciliation_reports, :bank_account_id
    add_index :accounting_bank_reconciliation_reports, [ :bank_account_id, :as_of ]

    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_bank_reconciliation_report_modification()
      RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'accounting_bank_reconciliation_reports are immutable';
      END;
      $$;

      CREATE TRIGGER enforce_bank_reconciliation_report_immutability
      BEFORE UPDATE OR DELETE ON accounting_bank_reconciliation_reports
      FOR EACH ROW EXECUTE FUNCTION prevent_bank_reconciliation_report_modification();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS enforce_bank_reconciliation_report_immutability ON accounting_bank_reconciliation_reports;"
    execute "DROP FUNCTION IF EXISTS prevent_bank_reconciliation_report_modification();"
    drop_table :accounting_bank_reconciliation_reports
  end
end

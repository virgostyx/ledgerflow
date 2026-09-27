class AddReportIndexes < ActiveRecord::Migration[8.1]
  # The 6 indexes from docs/dev/reports/spec.md §3, adapted to this app's real
  # column/table names (see docs/dev/reports/00-audit.md §1 for the mapping).
  # No `number` column exists on accounting_journal_entries (only `reference`,
  # a free string) — the journal+fiscal_year+number index becomes journal+
  # fiscal_year+reference, the closest real equivalent.
  disable_ddl_transaction!

  def change
    add_index :accounting_journal_entry_lines, [ :account_id, :entry_date, :id ],
               name: "idx_lines_account_date", algorithm: :concurrently

    add_index :accounting_journal_entry_lines, [ :partner_id, :account_id ],
               where: "lettering_id IS NULL", name: "idx_lines_partner_open",
               algorithm: :concurrently

    remove_index :accounting_journal_entry_lines, :lettering_id,
                  algorithm: :concurrently
    add_index :accounting_journal_entry_lines, :lettering_id,
               where: "lettering_id IS NOT NULL", name: "idx_lines_lettering",
               algorithm: :concurrently

    add_index :accounting_journal_entries, [ :entity_id, :fiscal_year_id, :entry_date ],
               where: "status = 1", name: "idx_entries_entity_period",
               algorithm: :concurrently

    add_index :accounting_journal_entries, [ :journal_id, :fiscal_year_id, :reference ],
               name: "idx_entries_journal_reference", algorithm: :concurrently

    remove_index :accounting_audit_logs, [ :auditable_type, :auditable_id ],
                  algorithm: :concurrently
    add_index :accounting_audit_logs, [ :auditable_type, :auditable_id, :created_at ],
               name: "idx_audit_object", algorithm: :concurrently
  end
end

class AddAmountResidualToJournalEntryLines < ActiveRecord::Migration[8.1]
  # docs/dev/reports/spec.md §7: cached "still to settle" amount for R04/R05, maintained
  # by the lettering service (Accounting::JournalEntryLine.resync_amount_residual!) rather
  # than a DB trigger, since it depends on accounting_line_allocations and
  # accounting_letterings — both written via update_all/nullify, which bypass AR callbacks.
  #
  # No separate `reconciliation_items` table is created: accounting_line_allocations
  # (dated via allocated_on) already plays that role for partial matches, and
  # accounting_letterings.lettered_on dates full ones — see docs/dev/reports/QUESTIONS.md.
  def up
    add_column :accounting_journal_entry_lines, :amount_residual, :decimal, precision: 15, scale: 2

    execute <<~SQL
      UPDATE accounting_journal_entry_lines l
      SET amount_residual = CASE
        WHEN l.lettering_id IS NOT NULL THEN 0
        ELSE l.debit + l.credit - COALESCE((
          SELECT SUM(al.amount) FROM accounting_line_allocations al
          WHERE al.debit_line_id = l.id OR al.credit_line_id = l.id
        ), 0)
      END;
    SQL

    change_column_null :accounting_journal_entry_lines, :amount_residual, false
  end

  def down
    remove_column :accounting_journal_entry_lines, :amount_residual
  end
end

# R17 (docs/dev/reports/spec.md §13): closing accruals/deferrals, plus the service period of an invoice
# line, which the cut-off lists read.
class CreateAccountingAccruals < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_accruals do |t|
      t.bigint  :entity_id,           null: false
      t.bigint  :fiscal_year_id,      null: false
      t.integer :accrual_type,        null: false
      t.string  :description,         null: false
      t.decimal :total_amount,        null: false, precision: 15, scale: 2
      t.date    :period_start,        null: false
      t.date    :period_end,          null: false
      t.bigint  :pl_account_id,       null: false
      t.bigint  :accrual_account_id,  null: false
      t.bigint  :source_journal_entry_id
      t.bigint  :journal_entry_id
      t.bigint  :reversal_entry_id
      t.timestamps
    end
    add_index :accounting_accruals, :entity_id
    add_index :accounting_accruals, :fiscal_year_id
    add_check_constraint :accounting_accruals, "total_amount > 0", name: "accruals_amount_positive"
    add_check_constraint :accounting_accruals, "period_end >= period_start", name: "accruals_period_order"

    add_column :accounting_invoice_lines, :service_start, :date
    add_column :accounting_invoice_lines, :service_end, :date
  end
end

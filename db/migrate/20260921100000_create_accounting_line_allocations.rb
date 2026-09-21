class CreateAccountingLineAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_line_allocations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :debit_line,  null: false, foreign_key: { to_table: :accounting_journal_entry_lines }
      t.references :credit_line, null: false, foreign_key: { to_table: :accounting_journal_entry_lines }
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.date    :allocated_on, null: false
      t.timestamps
    end
    add_check_constraint :accounting_line_allocations, "amount > 0", name: "chk_allocation_amount_positive"
    add_index :accounting_line_allocations, %i[debit_line_id credit_line_id], unique: true
  end
end

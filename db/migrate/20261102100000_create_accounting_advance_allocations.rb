# What an invoice settles of the advances paid to its supplier (document_type "advance", booked on 409000): the amount is in the currency of both
# (an advance is only settled by an invoice in the same currency). journal_entry_id stays empty while the invoice is a draft: the entry that
# moves the amount from the supplier account to 409000 is posted with the invoice.
class CreateAccountingAdvanceAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_advance_allocations do |t|
      t.references :entity,  null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: { to_table: :accounting_invoices }
      t.references :advance, null: false, foreign_key: { to_table: :accounting_invoices }
      t.references :journal_entry, foreign_key: { to_table: :accounting_journal_entries }
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.timestamps
    end
    add_check_constraint :accounting_advance_allocations, "amount > 0", name: "chk_advance_allocation_amount_positive"
    add_index :accounting_advance_allocations, %i[invoice_id advance_id], unique: true
  end
end

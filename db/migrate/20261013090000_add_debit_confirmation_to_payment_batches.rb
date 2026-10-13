# B01c: what the statement says of a payment batch. A payment is tied to the line of the statement that debited it and to the one entry made for it (one entry per payment,
# never two: unique); the batch says how and by whom its debit was confirmed, from the statement or by hand.
class AddDebitConfirmationToPaymentBatches < ActiveRecord::Migration[8.1]
  def change
    change_table :payment_items, bulk: true do |t|
      t.references :bank_transaction, foreign_key: { to_table: :accounting_bank_transactions }
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.datetime :confirmed_at
    end
    add_index :payment_items, :journal_entry_id, unique: true, where: "journal_entry_id IS NOT NULL", name: "index_payment_items_on_journal_entry_unique"

    change_table :payment_batches, bulk: true do |t|
      t.datetime :debited_at
      t.references :debited_by, foreign_key: { to_table: :users }
      t.string :debit_kind # "statement" or "manual"
      t.string :debit_reason
      t.string :debit_reference
      t.date :debit_date
    end
  end
end

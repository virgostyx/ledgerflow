class CreateAccountingPaymentBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_payment_batches do |t|
      t.references :entity,       null: false, foreign_key: { to_table: :entities }
      t.references :bank_account, null: false,
                   foreign_key: { to_table: :accounting_bank_accounts }
      t.references :journal_entry,
                   foreign_key: { to_table: :accounting_journal_entries }
      t.integer :status,                   null: false, default: 0
      t.date    :requested_execution_date, null: false
      t.string  :message_id
      t.text    :sepa_xml
      t.decimal :total_amount, precision: 15, scale: 2, null: false, default: 0
      t.datetime :generated_at
      t.datetime :executed_at

      t.timestamps
    end

    add_index :accounting_payment_batches, :message_id, unique: true

    create_table :accounting_payment_batch_lines do |t|
      t.references :entity,        null: false, foreign_key: { to_table: :entities }
      t.references :payment_batch, null: false,
                   foreign_key: { to_table: :accounting_payment_batches }
      t.references :invoice, null: false,
                   foreign_key: { to_table: :accounting_invoices }
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string  :remittance_information

      t.timestamps
    end
  end
end

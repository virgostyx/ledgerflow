class CreateAccountingRecurringInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_recurring_invoices do |t|
      t.references :entity,         null: false, foreign_key: true
      t.references :source_invoice, null: false, foreign_key: { to_table: :accounting_invoices }
      t.integer :frequency,  null: false, default: 0 # monthly: 0, quarterly: 1, yearly: 2
      t.date    :start_on,   null: false
      t.date    :end_on
      t.boolean :active,     null: false, default: true
      t.integer :runs_count, null: false, default: 0
      t.date    :last_run_on
      t.text    :last_error

      t.timestamps
    end

    add_reference :accounting_invoices, :recurring_invoice, foreign_key: { to_table: :accounting_recurring_invoices }
  end
end

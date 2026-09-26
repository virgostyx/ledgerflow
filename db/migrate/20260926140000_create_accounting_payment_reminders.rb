class CreateAccountingPaymentReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_payment_reminders do |t|
      t.references :entity,  null: false, foreign_key: true
      t.references :partner, null: false, foreign_key: { to_table: :accounting_partners }
      t.references :sent_by, null: false, foreign_key: { to_table: :users }
      t.integer  :level,     null: false # 1 courteous, 2 firm, 3 formal notice
      t.string   :recipient, null: false
      t.string   :subject,   null: false
      t.integer  :status,    null: false, default: 0 # queued: 0, sent: 1, failed: 2
      t.text     :error
      t.datetime :sent_at

      t.timestamps
    end

    create_table :accounting_payment_reminder_items do |t|
      t.references :entity,           null: false, foreign_key: true
      t.references :payment_reminder, null: false, foreign_key: { to_table: :accounting_payment_reminders }
      t.references :invoice,          null: false, foreign_key: { to_table: :accounting_invoices }
      t.decimal :amount_due, precision: 15, scale: 2, null: false # what was still due when the reminder was made

      t.timestamps
    end
  end
end

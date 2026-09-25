class CreateAccountingPeppolEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_peppol_events do |t|
      t.references :entity,  null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: { to_table: :accounting_invoices }
      t.integer  :kind,        null: false # sent: 0, delivered: 1, failed: 2
      t.text     :message
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :accounting_peppol_events, %i[invoice_id occurred_at]
  end
end

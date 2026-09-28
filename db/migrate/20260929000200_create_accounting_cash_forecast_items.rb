# R14 (docs/dev/reports/spec.md §12): manual and recurring cash items in one table
# (recurrence "once" = a manual item; the spec's two tables carry the same columns).
class CreateAccountingCashForecastItems < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_cash_forecast_items do |t|
      t.bigint  :entity_id,  null: false
      t.string  :label,      null: false
      t.integer :direction,  null: false, default: 1
      t.decimal :amount,     null: false, precision: 15, scale: 2
      t.integer :recurrence, null: false, default: 0
      t.date    :first_date, null: false
      t.date    :end_date
      t.boolean :active,     null: false, default: true
      t.timestamps
    end
    add_index :accounting_cash_forecast_items, :entity_id
    add_check_constraint :accounting_cash_forecast_items, "amount > 0", name: "cash_forecast_items_amount_positive"
  end
end

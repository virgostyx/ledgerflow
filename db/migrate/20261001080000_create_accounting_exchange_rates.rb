class CreateAccountingExchangeRates < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_exchange_rates do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :currency,  null: false, limit: 3
      t.date    :rate_date, null: false
      t.decimal :rate,      null: false, precision: 14, scale: 6 # EUR for 1 unit of currency, as on invoices
      t.timestamps
    end
    add_index :accounting_exchange_rates, %i[entity_id currency rate_date], unique: true, name: "idx_exchange_rates_on_entity_currency_date"
  end
end

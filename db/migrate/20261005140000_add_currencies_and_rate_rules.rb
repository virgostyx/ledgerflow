# F11: the currencies (code, decimals), the kinds and sources of the exchange rates, the rules of the entity (which rate, on which date, which
# accounts take the exchange differences, how unrealized ones are treated), a fixed currency on an account and a default one on a partner.
# Rates already entered are kept as they are, as closing rates on the date they were given.
class AddCurrenciesAndRateRules < ActiveRecord::Migration[8.1]
  def up
    create_table :currencies do |t|
      t.string  :code, null: false, limit: 3
      t.integer :decimals, null: false, default: 2
      t.timestamps
    end
    add_index :currencies, :code, unique: true
    Seeders::CurrenciesSeeder.call if defined?(Seeders::CurrenciesSeeder) && defined?(Accounting::Currency)

    change_table :accounting_exchange_rates do |t|
      t.integer  :rate_type, null: false, default: 3 # daily / monthly_average / closing / manual
      t.string   :source, null: false, default: "manual"
      t.datetime :imported_at
      t.text     :reason
      t.references :created_by, foreign_key: { to_table: :users }
    end
    # The rates entered so far served to value the foreign balances at closing (the revaluation): they stay closing rates, on the date given.
    execute "UPDATE accounting_exchange_rates SET rate_type = 2, reason = 'Entered before the multi-currency rules'"
    remove_index :accounting_exchange_rates, name: "idx_exchange_rates_on_entity_currency_date"
    add_index :accounting_exchange_rates, %i[entity_id currency rate_date rate_type source], unique: true, name: "idx_exchange_rates_unique"

    change_table :entities do |t|
      t.integer :rate_policy, null: false, default: 0       # daily / monthly_average / manual
      t.integer :rate_date_basis, null: false, default: 0   # document_date / accounting_date
      t.decimal :rate_alert_pct, precision: 5, scale: 2, null: false, default: 5
      t.string  :rate_fallback_currencies, array: true, null: false, default: []
      t.boolean :fx_realized_as_draft, null: false, default: false
      t.string  :fx_loss_account_code, null: false, default: "651200"
      t.string  :fx_gain_account_code, null: false, default: "751100"
      t.integer :fx_unrealized_loss, null: false, default: 0 # expense / ignore
      t.integer :fx_unrealized_gain, null: false, default: 0 # defer / recognize / ignore
    end

    add_column :accounting_invoices, :exchange_rate_reason, :text # present when the rate was typed by hand instead of taken from the official ones
    add_column :accounting_accounts, :currency, :string, limit: 3
    add_column :accounting_accounts, :revalue_at_closing, :boolean, null: false, default: false
    add_column :accounting_partners, :currency, :string, limit: 3, null: false, default: "EUR"
  end

  def down
    remove_column :accounting_partners, :currency
    remove_column :accounting_accounts, :revalue_at_closing
    remove_column :accounting_accounts, :currency
    remove_column :accounting_invoices, :exchange_rate_reason
    change_table :entities do |t|
      t.remove :fx_unrealized_gain, :fx_unrealized_loss, :fx_gain_account_code, :fx_loss_account_code, :fx_realized_as_draft,
               :rate_fallback_currencies, :rate_alert_pct, :rate_date_basis, :rate_policy
    end
    remove_index :accounting_exchange_rates, name: "idx_exchange_rates_unique"
    add_index :accounting_exchange_rates, %i[entity_id currency rate_date], unique: true, name: "idx_exchange_rates_on_entity_currency_date"
    change_table :accounting_exchange_rates do |t|
      t.remove_references :created_by, foreign_key: { to_table: :users }
      t.remove :reason, :imported_at, :source, :rate_type
    end
    drop_table :currencies
  end
end

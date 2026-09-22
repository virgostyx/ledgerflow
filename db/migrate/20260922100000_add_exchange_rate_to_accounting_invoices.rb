class AddExchangeRateToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :exchange_rate, :decimal, precision: 10, scale: 6, null: false, default: 1.0
  end
end

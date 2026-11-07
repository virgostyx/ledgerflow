# A cash journal can hold a foreign currency (a project cash box in kwacha). Every existing journal is in EUR; a bank account keeps its own currency.
class AddCurrencyToAccountingJournals < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_journals, :currency, :string, limit: 3, null: false, default: "EUR"
  end
end

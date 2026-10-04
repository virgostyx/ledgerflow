# F11: one convention for every exchange rate, the one of the ECB and of BudgetFlow: the number of units of foreign currency for 1 EUR
# (EUR amount = foreign amount / rate), stored with 8 decimals; amounts in foreign currency are numeric(18,4) and signed like the line
# (debit positive, credit negative). Until now rates were EUR for 1 unit, with 6 decimals, and amounts positive.
#
# What changes in existing data: each stored rate is inverted and rounded to 6 decimals (1 / 0.909091 = 1.100000: the figure typed is
# recovered, not an 8-decimal artefact of the inverse); each foreign amount on a credit line becomes negative. Debit and credit, which are in EUR,
# are not touched, so no balance and no report changes. Down: the same operations backwards (rates back to 6 decimals, which can differ in
# the last digit from what they were).
class UseForeignUnitsPerEurRates < ActiveRecord::Migration[8.1]
  VIEW = <<~SQL.freeze
    CREATE VIEW posted_lines AS
    SELECT l.id AS id, l.entity_id AS entity_id, e.id AS journal_entry_id, e.fiscal_year_id AS fiscal_year_id, e.journal_id AS journal_id,
           e.entry_date AS entry_date, e.reference AS reference, l.account_id AS account_id, l.partner_id AS partner_id, l.debit AS debit,
           l.credit AS credit, l.label AS label, l.vat_code AS vat_code, l.lettering_id AS lettering_id, l.currency AS currency,
           l.amount_currency AS amount_currency
    FROM accounting_journal_entry_lines l
    JOIN accounting_journal_entries e ON e.id = l.journal_entry_id
    WHERE e.status IN (1, 2);
  SQL

  def up
    execute "DROP VIEW posted_lines"
    change_column :accounting_journal_entry_lines, :amount_currency, :decimal, precision: 18, scale: 4
    change_column :accounting_journal_entry_lines, :exchange_rate,   :decimal, precision: 18, scale: 8
    change_column :accounting_invoices,            :exchange_rate,   :decimal, precision: 18, scale: 8, default: 1, null: false
    change_column :accounting_exchange_rates,      :rate,            :decimal, precision: 18, scale: 8
    invert_rates
    execute "UPDATE accounting_journal_entry_lines SET amount_currency = -ABS(amount_currency) WHERE credit > 0 AND amount_currency IS NOT NULL"
    execute "UPDATE accounting_journal_entry_lines SET amount_currency = ABS(amount_currency) WHERE debit > 0 AND amount_currency IS NOT NULL"
    execute VIEW
  end

  def down
    execute "DROP VIEW posted_lines"
    execute "UPDATE accounting_journal_entry_lines SET amount_currency = ABS(amount_currency) WHERE amount_currency IS NOT NULL"
    invert_rates
    change_column :accounting_exchange_rates,      :rate,            :decimal, precision: 14, scale: 6
    change_column :accounting_invoices,            :exchange_rate,   :decimal, precision: 10, scale: 6, default: 1, null: false
    change_column :accounting_journal_entry_lines, :exchange_rate,   :decimal, precision: 10, scale: 6
    change_column :accounting_journal_entry_lines, :amount_currency, :decimal, precision: 15, scale: 2
    execute VIEW
  end

  private

  # Rates of 1 are their own inverse; the others are inverted and rounded to 6 decimals (in both directions), never to zero.
  def invert_rates
    { accounting_journal_entry_lines: "exchange_rate", accounting_invoices: "exchange_rate", accounting_exchange_rates: "rate" }.each do |table, column|
      execute "UPDATE #{table} SET #{column} = GREATEST(ROUND(1 / #{column}, 6), 0.000001) WHERE #{column} IS NOT NULL AND #{column} > 0 AND #{column} <> 1"
    end
  end
end

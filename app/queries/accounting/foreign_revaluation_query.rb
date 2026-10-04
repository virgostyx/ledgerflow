# Foreign-currency balances still open at `as_of`, valued at the closing rate from Accounting::ExchangeRate (units of currency for 1 EUR, so EUR = foreign / rate): open
# receivables (40%), open payables (44%) and the balance of the foreign bank accounts (55%, or any account kept in a currency and flagged to be revalued). One row per kind and
# currency. `difference` is the unrealized exchange result in EUR (positive = gain, negative = loss); rate, revalued_eur
# and difference are nil when no rate is known on or before `as_of` (never guessed). Read-only: nothing is booked.
class Accounting::ForeignRevaluationQuery
  Row = Struct.new(:kind, :currency, :foreign_amount, :booked_eur, :rate, :revalued_eur, :difference, :account_ids, keyword_init: true)

  LINES = Accounting::OpenLineSql::LINES

  def initialize(as_of: Date.current)
    @as_of = as_of
  end

  def call
    (trade_rows(:customer) + trade_rows(:supplier) + bank_rows).map { |kind, currency, foreign, booked, accounts| row(kind, currency, foreign, booked, accounts) }
  end

  private

  # `foreign` and `booked` share the sign of the position (asset: debit, liability: credit).
  # `accounts`: the accounts the position is made of, for the drill-down to the general ledger (R02).
  def row(kind, currency, foreign, booked, accounts)
    rate = closing_rate(currency)
    revalued = rate && Fx::Convert.to_eur(foreign, rate)
    diff = revalued && (kind == :payable ? booked - revalued : revalued - booked)
    Row.new(kind: kind, currency: currency, foreign_amount: foreign, booked_eur: booked, rate: rate, revalued_eur: revalued, difference: diff, account_ids: accounts)
  end

  # nil when there is none: the row says "No rate" and the caller must ask for it, never guess.
  def closing_rate(currency)
    Fx::RateFor.closing(currency, @as_of)
  rescue Fx::MissingRate
    nil
  end

  # Open part of each foreign line: its EUR residual, and the same share of its foreign amount.
  def trade_rows(kind)
    residual = Accounting::OpenLineSql.residual(kind: kind, as_of: @as_of)
    Accounting::OpenLineSql.open_scope(kind: kind, as_of: @as_of).where.not(currency: "EUR").group(:currency)
      .having("SUM(#{residual}) <> 0")
      .pluck(Arel.sql("#{LINES}.currency"),
             Arel.sql("SUM(ABS(#{LINES}.amount_currency) * (#{residual}) / NULLIF(#{LINES}.debit + #{LINES}.credit, 0))"),
             Arel.sql("SUM(#{residual})"), Arel.sql("ARRAY_AGG(DISTINCT #{LINES}.account_id)"))
      .map { |currency, foreign, booked, accounts| [ kind == :customer ? :receivable : :payable, currency, foreign, booked, accounts ] }
  end

  def bank_rows
    Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = #{LINES}.journal_entry_id")
      .joins("JOIN accounting_accounts a ON a.id = #{LINES}.account_id")
      .where("e.status IN (?) AND e.entry_date <= ?", Accounting::JournalEntry.ledger_status_values, @as_of)
      .where("a.code LIKE '55%' OR (a.revalue_at_closing AND a.code NOT LIKE '40%' AND a.code NOT LIKE '44%')")
      .where.not(currency: "EUR").group(:currency)
      .pluck(Arel.sql("#{LINES}.currency"), Arel.sql("SUM(#{LINES}.amount_currency)"), Arel.sql("SUM(#{LINES}.debit - #{LINES}.credit)"),
             Arel.sql("ARRAY_AGG(DISTINCT #{LINES}.account_id)"))
      .map { |currency, foreign, booked, accounts| [ :bank, currency, foreign, booked, accounts ] }
  end
end

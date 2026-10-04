# Foreign-currency balances still open at `as_of`, valued at the closing rate from Accounting::ExchangeRate: open
# receivables (40%), open payables (44%) and the balance of the foreign bank accounts (55%). One row per kind and
# currency. `difference` is the unrealized exchange result in EUR (positive = gain, negative = loss); rate, revalued_eur
# and difference are nil when no rate is known on or before `as_of` (never guessed). Read-only: nothing is booked.
class Accounting::ForeignRevaluationQuery
  Row = Struct.new(:kind, :currency, :foreign_amount, :booked_eur, :rate, :revalued_eur, :difference, keyword_init: true)

  LINES = Accounting::OpenLineSql::LINES

  def initialize(as_of: Date.current)
    @as_of = as_of
  end

  def call
    (trade_rows(:customer) + trade_rows(:supplier) + bank_rows).map { |kind, currency, foreign, booked| row(kind, currency, foreign, booked) }
  end

  private

  # `foreign` and `booked` share the sign of the position (asset: debit, liability: credit).
  def row(kind, currency, foreign, booked)
    rate = Accounting::ExchangeRate.rate_for(currency, @as_of)
    revalued = rate && (foreign * rate).round(2)
    diff = revalued && (kind == :payable ? booked - revalued : revalued - booked)
    Row.new(kind: kind, currency: currency, foreign_amount: foreign, booked_eur: booked, rate: rate, revalued_eur: revalued, difference: diff)
  end

  # Open part of each foreign line: its EUR residual, and the same share of its foreign amount.
  def trade_rows(kind)
    residual = Accounting::OpenLineSql.residual(kind: kind, as_of: @as_of)
    Accounting::OpenLineSql.open_scope(kind: kind, as_of: @as_of).where.not(currency: "EUR").group(:currency)
      .having("SUM(#{residual}) <> 0")
      .pluck(Arel.sql("#{LINES}.currency"),
             Arel.sql("SUM(#{LINES}.amount_currency * (#{residual}) / NULLIF(#{LINES}.debit + #{LINES}.credit, 0))"),
             Arel.sql("SUM(#{residual})"))
      .map { |currency, foreign, booked| [ kind == :customer ? :receivable : :payable, currency, foreign, booked ] }
  end

  def bank_rows
    sign = "CASE WHEN #{LINES}.debit > 0 THEN 1 ELSE -1 END"
    Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = #{LINES}.journal_entry_id")
      .joins("JOIN accounting_accounts a ON a.id = #{LINES}.account_id")
      .where("e.status IN (?) AND e.entry_date <= ?", Accounting::JournalEntry.ledger_status_values, @as_of)
      .where("a.code LIKE '55%'").where.not(currency: "EUR").group(:currency)
      .pluck(Arel.sql("#{LINES}.currency"), Arel.sql("SUM(#{sign} * #{LINES}.amount_currency)"), Arel.sql("SUM(#{LINES}.debit - #{LINES}.credit)"))
      .map { |currency, foreign, booked| [ :bank, currency, foreign, booked ] }
  end
end

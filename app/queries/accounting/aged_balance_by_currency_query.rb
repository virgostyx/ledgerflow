# R04 grouped by currency (F11): what is still open at `as_of` per currency and partner, in the currency, in the EUR the books carry (the total of R04,
# Accounting::AgedBalanceQuery) and, with `at_closing_rate`, in EUR at the closing rate of the date (`rate` and `revalued_eur` stay nil without one:
# a rate is never guessed). A line in EUR is its own amount.
class Accounting::AgedBalanceByCurrencyQuery
  LINES = Accounting::OpenLineSql::LINES
  Row = Struct.new(:currency, :partner_name, :foreign_amount, :booked_eur, :rate, :revalued_eur, keyword_init: true)

  def initialize(kind:, as_of: Date.current, at_closing_rate: false)
    @kind = kind.to_sym
    @as_of = as_of
    @at_closing_rate = at_closing_rate
  end

  def call
    residual = Accounting::OpenLineSql.residual(kind: @kind, as_of: @as_of)
    foreign = "CASE WHEN #{LINES}.currency = 'EUR' OR #{LINES}.amount_currency IS NULL THEN (#{residual}) " \
              "ELSE ABS(#{LINES}.amount_currency) * (#{residual}) / NULLIF(#{LINES}.debit + #{LINES}.credit, 0) END"
    Accounting::OpenLineSql.open_scope(kind: @kind, as_of: @as_of).group(Arel.sql("#{LINES}.currency"), Arel.sql("p.name"))
      .having("SUM(#{residual}) <> 0").order(Arel.sql("#{LINES}.currency"), Arel.sql("p.name"))
      .pluck(Arel.sql("#{LINES}.currency"), Arel.sql("p.name"), Arel.sql("SUM(#{foreign})"), Arel.sql("SUM(#{residual})"))
      .map { |currency, name, foreign_amount, booked| row(currency, name, BigDecimal(foreign_amount.to_s), BigDecimal(booked.to_s)) }
  end

  private

  def row(currency, name, foreign_amount, booked)
    rate = closing_rate(currency) if @at_closing_rate && currency != "EUR"
    revalued = if !@at_closing_rate then nil
    elsif currency == "EUR" then booked
    elsif rate then Fx::Convert.to_eur(foreign_amount, rate)
    end
    Row.new(currency: currency, partner_name: name, foreign_amount: foreign_amount, booked_eur: booked, rate: rate, revalued_eur: revalued)
  end

  def closing_rate(currency)
    Fx::RateFor.closing(currency, @as_of)
  rescue Fx::MissingRate
    nil
  end
end

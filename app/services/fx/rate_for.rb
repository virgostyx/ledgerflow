# The exchange rate of an operation (F11), from the rules of the entity (`rate_policy`, `rate_date_basis`): units of currency for 1 EUR.
# Nothing is fetched from the network here, and a rate that is missing is never replaced by another one: Fx::MissingRate says which, on which date.
# The one exception is a currency the entity turned the fallback on for (`rate_fallback_currencies`): the last daily rate of the previous 7 days,
# which covers a weekend or a bank holiday and nothing more.
module Fx::RateFor
  FALLBACK_DAYS = 7

  # `document_date` and `accounting_date` are the two dates the operation has; the entity says which counts.
  def self.call(currency, document_date:, accounting_date: document_date, entity: ActsAsTenant.current_tenant)
    currency = currency.to_s.upcase
    return BigDecimal("1") if currency == "EUR"

    date = entity.accounting_date? ? accounting_date : document_date
    rate = by_policy(currency, date, entity) || fallback(currency, date, entity)
    rate || raise(Fx::MissingRate.new(currency, date))
  end

  # The rate that values the balances at a closing date: the one typed or fixed as "closing" for that date, never another kind.
  def self.closing(currency, date)
    return BigDecimal("1") if currency.to_s.upcase == "EUR"

    Accounting::ExchangeRate.closing.where(currency: currency.to_s.upcase, rate_date: date).order(:id).last&.rate || raise(Fx::MissingRate.new(currency.to_s.upcase, date, kind: "closing"))
  end

  def self.by_policy(currency, date, entity)
    scope = Accounting::ExchangeRate.where(currency: currency)
    manual = scope.manual.where(rate_date: date).order(:id).last&.rate
    return manual if manual || entity.rates_manual?

    kind = entity.rates_monthly_average? ? scope.monthly_average.where(rate_date: date.beginning_of_month) : scope.daily.where(rate_date: date)
    kind.order(:id).last&.rate
  end
  private_class_method :by_policy

  def self.fallback(currency, date, entity)
    return unless entity.rate_fallback_currencies.include?(currency) && entity.rates_daily?

    Accounting::ExchangeRate.daily.where(currency: currency, rate_date: (date - FALLBACK_DAYS)...date).order(rate_date: :desc, id: :desc).pick(:rate)
  end
  private_class_method :fallback
end

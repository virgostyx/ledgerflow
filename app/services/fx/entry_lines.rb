# The lines of a manual entry as the form sends them (F11): per line a currency, an amount in that currency (positive) and, for those who may override
# rates, a rate. The rate is the official one of the date unless one was typed with a reason (Fx::RateGuard); the euros are amount / rate on the side
# the person filled (or the side of the euros already typed); `amount_currency` is signed like the line. A line in EUR is left alone.
# => Result(lines, error, warning); an error is the message to show, and the entry is not saved.
module Fx::EntryLines
  Result = Struct.new(:lines, :error, :warning)

  def self.call(lines, date:, reason: nil, user: nil)
    warnings = []
    converted = {}
    lines.each do |key, attrs|
      attrs = attrs.to_h.stringify_keys
      outcome = convert(attrs, date, reason, user, warnings)
      return Result.new(nil, outcome, nil) if outcome.is_a?(String)

      converted[key] = outcome
    end
    Result.new(converted, nil, warnings.first)
  end

  def self.convert(attrs, date, reason, user, warnings)
    attrs = attrs.except("side") if attrs["currency"].to_s.upcase.in?([ "", "EUR" ]) || attrs["amount_currency"].to_s.strip.empty?
    currency = attrs["currency"].to_s.upcase
    return attrs if currency.blank? || currency == "EUR" || attrs["_destroy"].to_s == "1" || attrs["amount_currency"].to_s.strip.empty?

    amount = BigDecimal(attrs["amount_currency"].to_s.tr(",", "."))
    return "The amount in #{currency} must be positive." unless amount.positive?

    rate = rate_for(attrs, currency, date, reason, user, warnings)
    return rate if rate.is_a?(String)

    side = attrs["side"].presence&.to_sym || (attrs["credit"].to_s.to_d.positive? ? :credit : :debit)
    eur = Fx::Convert.to_eur(amount, rate)
    attrs.except("side").merge("currency" => currency, "amount_currency" => (side == :credit ? -amount : amount), "exchange_rate" => rate,
                               "debit" => side == :debit ? eur : 0, "credit" => side == :credit ? eur : 0)
  rescue ArgumentError
    "The amount in #{attrs['currency']} is not a number."
  end
  private_class_method :convert

  # The official rate, unless a person who may override typed another one: then it goes through the guard (a reason, and a warning for a big gap).
  def self.rate_for(attrs, currency, date, reason, user, warnings)
    typed = BigDecimal(attrs["exchange_rate"].to_s.strip.tr(",", ".")) if attrs["exchange_rate"].to_s.strip.present?
    official = begin
      Fx::RateFor.call(currency, document_date: date, accounting_date: date)
    rescue Fx::MissingRate => e
      missing = e
      nil
    end
    return official || missing.message unless typed && typed != official && may_override?(user)

    checked = Fx::RateGuard.call(currency: currency, date: date, rate: typed, reason: reason, user: user)
    warnings << checked.warning if checked.warning
    checked.rate
  rescue Fx::MissingRate, Fx::RateRefused => e
    e.message
  end
  private_class_method :rate_for

  def self.may_override?(user)
    user.nil? || Accounting::ExchangeRatePolicy.new(user, Accounting::ExchangeRate).create?
  end
  private_class_method :may_override?
end

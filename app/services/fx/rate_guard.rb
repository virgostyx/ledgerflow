# Checks the rate an operation wants to use (F11). The official rate of the date (Fx::RateFor) needs no reason; any other is typed by hand: it needs a
# reason and, when a person does it, the right `rates.override`. It is accepted even when no official rate exists for the date (a bank gave it), and
# a rate that strays from the official one by more than the entity's alert comes back with a warning. Raises Fx::MissingRate when there is no official
# rate and no hand-typed one, Fx::RateRefused for the rest. => Result(rate, warning)
module Fx::RateGuard
  Result = Struct.new(:rate, :warning)

  def self.call(currency:, date:, rate:, reason: nil, user: nil, entity: ActsAsTenant.current_tenant)
    return Result.new(BigDecimal("1"), nil) if currency.to_s.upcase == "EUR"

    official = official_rate(currency, date, entity)
    return Result.new(rate, nil) if official && rate == official
    raise missing_or_different(currency, date, rate, official) if reason.blank?

    ensure_allowed!(user, entity)
    Result.new(rate, warning(rate, official, entity))
  end

  def self.official_rate(currency, date, entity)
    Fx::RateFor.call(currency, document_date: date, accounting_date: date, entity: entity)
  rescue Fx::MissingRate
    nil
  end
  private_class_method :official_rate

  def self.missing_or_different(currency, date, rate, official)
    return Fx::MissingRate.new(currency.to_s.upcase, date) unless official

    Fx::RateRefused.new("The #{currency} rate #{rate.to_s('F')} is not the rate of #{Accounting::DatePresenter.new(date).format} (#{official.to_s('F')}): " \
                        "give a reason to use another one.")
  end
  private_class_method :missing_or_different

  def self.ensure_allowed!(user, entity)
    return unless user
    return if UserEntity.find_by(user: user, entity: entity)&.allows?("rates.override")

    raise Fx::RateRefused, "You are not allowed to use a rate other than the official one."
  end
  private_class_method :ensure_allowed!

  def self.warning(rate, official, entity)
    return unless official

    deviation = ((rate - official).abs / official * 100)
    return unless deviation > entity.rate_alert_pct

    "The rate #{rate.to_s('F')} is #{deviation.round(1).to_s('F')} % away from the official rate #{official.to_s('F')} (alert at #{entity.rate_alert_pct.to_s('F')} %)."
  end
  private_class_method :warning
end

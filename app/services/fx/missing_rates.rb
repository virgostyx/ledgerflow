# The rates that are missing for the currencies in use (F11), over the last 30 days (what a person may still enter documents for), as the entity's
# rules would look for them: each working day with no rate for the daily policy (weekends and bank holidays publish none, today is not published yet),
# each month for the monthly average. Nothing for a manual policy: a person types the rate. => [Missing(currency, dates)]
module Fx::MissingRates
  WINDOW = 30
  Missing = Struct.new(:currency, :dates)

  def self.call(today: Date.current, entity: ActsAsTenant.current_tenant)
    return [] if entity.rates_manual?

    Fx::CurrenciesInUse.call.filter_map do |currency|
      dates = (entity.rates_monthly_average? ? months(today) : working_days(today)).reject { |date| rate?(currency, date, entity) }
      Missing.new(currency, dates) if dates.any?
    end
  end

  def self.working_days(today) = (today - WINDOW...today).select(&:on_weekday?)

  def self.months(today) = (today - WINDOW...today).map(&:beginning_of_month).uniq

  # Looked up with the rules themselves, the fallback included: a weekend or a holiday the entity covers is not missing.
  def self.rate?(currency, date, entity)
    Fx::RateFor.call(currency, document_date: date, accounting_date: date, entity: entity)
    true
  rescue Fx::MissingRate
    false
  end
  private_class_method :rate?
end

# Closing and spot rates kept by the entity: EUR for 1 unit of `currency` (same convention as invoices).
class Accounting::ExchangeRate < ApplicationRecord
  self.table_name = "accounting_exchange_rates"

  acts_as_tenant :entity

  validates :currency,  format: { with: /\A[A-Z]{3}\z/ }, exclusion: { in: %w[EUR] }
  validates :rate_date, presence: true, uniqueness: { scope: %i[entity_id currency] }
  validates :rate,      numericality: { greater_than: 0 }

  before_validation { self.currency = currency.to_s.upcase.presence }

  # Latest rate known on or before `date`; nil when none (the caller must ask the accountant, never guess).
  def self.rate_for(currency, date)
    return BigDecimal("1") if currency.to_s.upcase == "EUR"

    where(currency: currency.to_s.upcase).where(rate_date: ..date).order(rate_date: :desc).pick(:rate)
  end
end

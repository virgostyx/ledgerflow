# Rates kept by the entity: units of `currency` for 1 EUR (the ECB's convention, the same everywhere: EUR = foreign / rate), 8 decimals.
class Accounting::ExchangeRate < ApplicationRecord
  self.table_name = "accounting_exchange_rates"

  acts_as_tenant :entity

  # daily: the ECB's reference rate of a day; monthly_average: the InforEuro rate of a month (dated the 1st); closing: the rate that values the
  # balances at a closing date; manual: typed by a person, with a reason.
  enum :rate_type, { daily: 0, monthly_average: 1, closing: 2, manual: 3 }

  autofilter_column :rate_date, sql: "accounting_exchange_rates.rate_date", type: :date
  autofilter_column :currency,  sql: "accounting_exchange_rates.currency", type: :string
  autofilter_column :rate,      sql: "accounting_exchange_rates.rate", type: :decimal
  autofilter_column :rate_type, sql: "accounting_exchange_rates.rate_type", type: :enum
  autofilter_column :source,    sql: "accounting_exchange_rates.source", type: :string

  belongs_to :created_by, class_name: "User", optional: true

  validates :currency,  format: { with: /\A[A-Z]{3}\z/ }, exclusion: { in: %w[EUR] }
  validates :rate_date, presence: true, uniqueness: { scope: %i[entity_id currency rate_type source] }
  validates :rate,      numericality: { greater_than: 0 }
  validates :source,    presence: true
  validates :reason,    presence: true, if: :manual?

  before_validation { self.currency = currency.to_s.upcase.presence }
end

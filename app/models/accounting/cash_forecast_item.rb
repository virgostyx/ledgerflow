# A manual (recurrence :once) or recurring (payroll, rent, insurance) cash movement that the
# R14 forecast adds to the open invoices (docs/dev/reports/spec.md §12).
class Accounting::CashForecastItem < ApplicationRecord
  self.table_name = "accounting_cash_forecast_items"

  acts_as_tenant :entity

  enum :direction,  { inflow: 0, outflow: 1 }
  enum :recurrence, { once: 0, monthly: 1, quarterly: 2, yearly: 3 }
  STEP_MONTHS = { monthly: 1, quarterly: 3, yearly: 12 }.freeze

  validates :label, :first_date, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validate  :end_date_not_before_first_date

  scope :active, -> { where(active: true) }

  def occurrences_between(from, to)
    return [] unless active

    last = [ to, end_date ].compact.min
    return (first_date.between?(from, last) ? [ first_date ] : []) if once?

    step = STEP_MONTHS.fetch(recurrence.to_sym)
    (0..).lazy.map { |n| first_date.advance(months: n * step) }
         .take_while { |date| date <= last }.select { |date| date >= from }.to_a
  end

  private

  def end_date_not_before_first_date
    errors.add(:end_date, :invalid) if end_date && first_date && end_date < first_date
  end
end

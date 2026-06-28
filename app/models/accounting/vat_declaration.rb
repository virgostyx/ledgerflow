class Accounting::VatDeclaration < ApplicationRecord
  self.table_name = "accounting_vat_declarations"

  acts_as_tenant :entity

  belongs_to :fiscal_year, class_name: "Accounting::FiscalYear"

  enum :status,      { draft: 0, submitted: 1, accepted: 2 }
  enum :period_type, { monthly: 0, quarterly: 1 }

  validates :period_start, presence: true
  validates :period_end,   presence: true
  validates :period_type,  presence: true

  validate :period_end_after_period_start

  def grid_total(code)
    BigDecimal(grids[code] || "0")
  end

  private

  def period_end_after_period_start
    return unless period_start && period_end
    errors.add(:period_end, :greater_than, count: period_start) if period_end < period_start
  end
end

class Accounting::FiscalYear < ApplicationRecord
  self.table_name = "accounting_fiscal_years"

  acts_as_tenant :entity

  enum :status, { open: 0, pre_closing: 1, closed: 2 }

  validates :year,       presence: true, uniqueness: { scope: :entity_id }
  validates :start_date, presence: true
  validates :end_date,   presence: true
  validates :status,     presence: true
  validate  :end_date_after_start_date
  validate  :only_one_open_at_a_time, if: :open?

  scope :open_years, -> { where(status: :open) }
  scope :current,    -> { open_years.first }

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, :invalid) if end_date <= start_date
  end

  def only_one_open_at_a_time
    scope = Accounting::FiscalYear.open_years
    scope = scope.where.not(id: id) if persisted?
    errors.add(:status, :taken) if scope.exists?
  end
end

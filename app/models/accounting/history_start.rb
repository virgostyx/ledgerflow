# B03a: from when the books of a company (or of one of its fiscal years) can be shown as they were known. Before it, no view.
class Accounting::HistoryStart < ApplicationRecord
  self.table_name = "accounting_history_starts"

  acts_as_tenant :entity

  belongs_to :fiscal_year, class_name: "Accounting::FiscalYear", optional: true

  validates :starts_at, presence: true
  validates :fiscal_year_id, uniqueness: { scope: :entity_id }
end

# The depreciation of one fixed asset booked for one fiscal year (with its journal entry). At most one per
# asset and year: it is what makes posting the depreciation idempotent.
class Accounting::DepreciationEntry < ApplicationRecord
  self.table_name = "accounting_depreciation_entries"

  acts_as_tenant :entity

  belongs_to :fixed_asset,   class_name: "Accounting::FixedAsset"
  belongs_to :fiscal_year,   class_name: "Accounting::FiscalYear"
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry"

  validates :amount, numericality: { greater_than: 0 }
  validates :fixed_asset_id, uniqueness: { scope: :fiscal_year_id }
end

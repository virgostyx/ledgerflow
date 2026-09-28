# docs/dev/reports/spec.md §10: a VAT nature. Not tenant-scoped: VAT law reference data.
# Read through Accounting::VatGrid (cached); saving here resets that cache.
class Accounting::VatCode < ApplicationRecord
  self.table_name = "accounting_vat_codes"

  enum :sens,   { sale: 0, purchase: 1 }
  enum :nature, { domestic: 0, intracom_goods: 1, intracom_services: 2,
                  construction_reverse_charge: 3, export: 4, exempt: 5 }

  has_many :grid_mappings, class_name: "Accounting::VatGridMapping"

  validates :code, presence: true, uniqueness: true
  validates :label, presence: true

  after_commit { Accounting::VatGrid.reset! }
end

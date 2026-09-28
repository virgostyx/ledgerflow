# docs/dev/reports/spec.md §10: a VAT nature (sale side only — see the migration).
# Not tenant-scoped: this is VAT law reference data, not per-entity data.
class Accounting::VatCode < ApplicationRecord
  self.table_name = "accounting_vat_codes"

  enum :sens,   { sale: 0 }
  enum :nature, { domestic: 0, intracom_goods: 1, intracom_services: 2,
                  construction_reverse_charge: 3, export: 4, exempt: 5 }

  has_many :grid_mappings, class_name: "Accounting::VatGridMapping"

  validates :code, presence: true, uniqueness: true
  validates :label, presence: true
end

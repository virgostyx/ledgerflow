# docs/dev/reports/spec.md §10: for a vat_code and document type, which grid(s) it goes to.
class Accounting::VatGridMapping < ApplicationRecord
  self.table_name = "accounting_vat_grid_mappings"

  enum :document_type, { invoice: 0, credit_note: 1 }

  belongs_to :vat_code, class_name: "Accounting::VatCode"

  validates :document_type, presence: true
  validates :vat_code_id, uniqueness: { scope: :document_type }
end

class Accounting::Partner < ApplicationRecord
  self.table_name = "accounting_partners"

  BELGIAN_VAT_FORMAT  = /\ABE[01]\d{9}\z/
  BELGIAN_IBAN_FORMAT = /\ABE\d{14}\z/

  enum :partner_type, { customer: 0, supplier: 1, both: 2 }

  validates :name,         presence: true
  validates :partner_type, presence: true
  validates :vat_number,   format: { with: BELGIAN_VAT_FORMAT },  allow_blank: true
  validates :iban,         format: { with: BELGIAN_IBAN_FORMAT }, allow_blank: true

  has_many :journal_entry_lines, class_name: "Accounting::JournalEntryLine",
                                  foreign_key: :partner_id,
                                  inverse_of:  :partner

  scope :active,    -> { where(active: true) }
  scope :customers, -> { where(partner_type: %i[customer both]) }
  scope :suppliers, -> { where(partner_type: %i[supplier both]) }
end

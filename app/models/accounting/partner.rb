class Accounting::Partner < ApplicationRecord
  self.table_name = "accounting_partners"

  acts_as_tenant :entity
  broadcasts_refreshes_to ->(r) { [ r.entity, :partners ] }

  BELGIAN_VAT_FORMAT = /\ABE[01]\d{9}\z/

  enum :partner_type, { customer: 0, supplier: 1, both: 2 }

  validates :name,         presence: true
  validates :partner_type, presence: true
  validates :vat_number,   format: { with: BELGIAN_VAT_FORMAT }, allow_blank: true

  validate :iban_format

  has_many :journal_entry_lines, class_name: "Accounting::JournalEntryLine",
                                  foreign_key: :partner_id,
                                  inverse_of:  :partner

  scope :active,    -> { where(active: true) }
  scope :customers, -> { where(partner_type: %i[customer both]) }
  scope :suppliers, -> { where(partner_type: %i[supplier both]) }

  def sepa_payable?
    iban.present? && IBANTools::IBAN.valid?(iban)
  end

  private

  def iban_format
    return if iban.blank?
    errors.add(:iban, :invalid) unless IBANTools::IBAN.valid?(iban)
  end

  def self.filter_by(q)
    rel = matching(partner_type: q[:partner_type], country: q[:country]).search(q[:q], "name", "vat_number", "city")
    q[:inactive] == "1" ? rel : rel.active
  end
end

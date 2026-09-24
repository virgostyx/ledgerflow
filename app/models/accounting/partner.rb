class Accounting::Partner < ApplicationRecord
  self.table_name = "accounting_partners"

  acts_as_tenant :entity
  broadcasts_refreshes_to ->(r) { [ r.entity, :partners ] }

  # National part of the VAT number per EU country prefix (checked after the 2-letter prefix)
  EU_VAT_FORMATS = {
    "AT" => /\AU\d{8}\z/,
    "BE" => /\A[01]\d{9}\z/,
    "BG" => /\A\d{9,10}\z/,
    "CY" => /\A\d{8}[A-Z]\z/,
    "CZ" => /\A\d{8,10}\z/,
    "DE" => /\A\d{9}\z/,
    "DK" => /\A\d{8}\z/,
    "EE" => /\A\d{9}\z/,
    "EL" => /\A\d{9}\z/,
    "ES" => /\A[A-Z0-9]\d{7}[A-Z0-9]\z/,
    "FI" => /\A\d{8}\z/,
    "FR" => /\A[A-Z0-9]{2}\d{9}\z/,
    "HR" => /\A\d{11}\z/,
    "HU" => /\A\d{8}\z/,
    "IE" => /\A\d{7}[A-Z]{1,2}\z/,
    "IT" => /\A\d{11}\z/,
    "LT" => /\A(\d{9}|\d{12})\z/,
    "LU" => /\A\d{8}\z/,
    "LV" => /\A\d{11}\z/,
    "MT" => /\A\d{8}\z/,
    "NL" => /\A\d{9}B\d{2}\z/,
    "PL" => /\A\d{10}\z/,
    "PT" => /\A\d{9}\z/,
    "RO" => /\A\d{2,10}\z/,
    "SE" => /\A\d{12}\z/,
    "SI" => /\A\d{8}\z/,
    "SK" => /\A\d{10}\z/
  }.freeze

  # ISO-3166 country codes of EU member states (Greece is "GR" here, "EL" in EU_VAT_FORMATS)
  EU_COUNTRIES = %w[AT BE BG CY CZ DE DK EE GR ES FI FR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK].freeze

  enum :partner_type, { customer: 0, supplier: 1, both: 2 }

  autofilter_column :name,         sql: "accounting_partners.name", type: :string, filter: false
  autofilter_column :partner_type, sql: "accounting_partners.partner_type", type: :enum
  autofilter_column :vat_number,   sql: "accounting_partners.vat_number", type: :string, filter: false
  autofilter_column :country,      sql: "accounting_partners.country", type: :string

  validates :name,         presence: true
  validates :partner_type, presence: true

  validate :vat_number_format
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

  def eu_country?
    EU_COUNTRIES.include?(country)
  end

  def domestic?
    country == "BE"
  end

  # Shared with Entity: the country prefix must be an EU one and the rest must fit that country's format.
  def self.valid_vat_number?(number)
    format = EU_VAT_FORMATS[number[0, 2]]
    format.present? && format.match?(number[2..])
  end

  private

  def vat_number_format
    errors.add(:vat_number, :invalid) unless vat_number.blank? || self.class.valid_vat_number?(vat_number)
  end

  def iban_format
    return if iban.blank?
    errors.add(:iban, :invalid) unless IBANTools::IBAN.valid?(iban)
  end

  def self.filter_by(q)
    rel = matching(partner_type: q[:partner_type], country: q[:country]).search(q[:q], "name", "vat_number", "city")
    q[:inactive] == "1" ? rel : rel.active
  end
end

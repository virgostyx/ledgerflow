class Accounting::Invoice < ApplicationRecord
  self.table_name = "accounting_invoices"

  acts_as_tenant :entity

  include AASM
  include Accounting::MonetaryPrecision
  include Accounting::FiscalYearScoped

  enum :invoice_type,   { customer: 0, supplier: 1 }
  enum :status,         { draft: 0, posted: 1, paid: 2, cancelled: 3 }
  enum :peppol_status,  { not_sent: 0, queued: 1, delivered: 2, failed: 3 }

  belongs_to :partner,       class_name: "Accounting::Partner"
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true
  belongs_to :journal,       class_name: "Accounting::Journal", optional: true
  has_many   :lines,         class_name: "Accounting::InvoiceLine",
                             foreign_key: :invoice_id, dependent: :destroy,
                             inverse_of: :invoice

  accepts_nested_attributes_for :lines, allow_destroy: true, reject_if: :all_blank

  validates :invoice_type, presence: true
  validates :invoice_date, presence: true
  validates :partner,      presence: true

  validate :journal_matches_invoice_type, if: -> { journal.present? }

  aasm column: :status, enum: true do
    state :draft, initial: true
    state :posted
    state :paid
    state :cancelled

    event :post do
      transitions from: :draft, to: :posted
    end

    event :pay do
      transitions from: :posted, to: :paid
    end

    event :cancel do
      transitions from: :draft, to: :cancelled
    end
  end

  def compute_totals
    self.subtotal_excl_vat = lines.sum(&:subtotal_excl_vat)
    self.vat_amount        = lines.sum(&:vat_amount)
    self.total_incl_vat    = lines.sum(&:total_incl_vat)
  end

  private

  def journal_matches_invoice_type
    expected = customer? ? "sale" : "purchase"
    return if journal.journal_type == expected
    errors.add(:journal, "must be a #{expected} journal")
  end
end

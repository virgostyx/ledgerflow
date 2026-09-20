class Accounting::Invoice < ApplicationRecord
  self.table_name = "accounting_invoices"

  acts_as_tenant :entity
  broadcasts_refreshes_to ->(r) { [ r.entity, :invoices ] }

  include AASM
  include Accounting::MonetaryPrecision
  include Accounting::FiscalYearScoped

  enum :invoice_type,   { customer: 0, supplier: 1 }
  enum :status,         { draft: 0, posted: 1, paid: 2, cancelled: 3 }
  enum :peppol_status,  { not_sent: 0, queued: 1, delivered: 2, failed: 3 }

  belongs_to :partner,       class_name: "Accounting::Partner"
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true
  belongs_to :journal,       class_name: "Accounting::Journal", optional: true
  belongs_to :cash_journal,  class_name: "Accounting::Journal", optional: true
  has_many   :lines,         class_name: "Accounting::InvoiceLine",
                             foreign_key: :invoice_id, dependent: :destroy,
                             inverse_of: :invoice

  accepts_nested_attributes_for :lines, allow_destroy: true, reject_if: :all_blank

  validates :invoice_type, presence: true
  validates :invoice_date, presence: true
  validates :partner,      presence: true

  validate :journal_matches_invoice_type, if: -> { journal.present? }
  validate :cash_journal_is_cash, if: -> { cash_journal.present? }

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

    event :reopen do
      transitions from: :paid, to: :posted
    end

    event :cancel do
      transitions from: %i[draft posted], to: :cancelled
    end
  end

  def compute_totals
    self.subtotal_excl_vat = lines.sum(&:subtotal_excl_vat)
    self.vat_amount        = lines.sum(&:vat_amount)
    self.total_incl_vat    = lines.sum(&:total_incl_vat)
  end

  # Customer receipts credit the receivable through lines linked to the invoice (journal_entry_lines.invoice_id).
  def paid_amount
    Accounting::JournalEntryLine.where(invoice_id: id).sum(:credit)
  end

  def remaining_amount
    [ total_incl_vat - paid_amount, 0 ].max
  end

  def overpaid_amount
    [ paid_amount - total_incl_vat, 0 ].max
  end

  private

  def journal_matches_invoice_type
    expected = customer? ? "sale" : "purchase"
    return if journal.journal_type == expected
    errors.add(:journal, "must be a #{expected} journal")
  end

  def cash_journal_is_cash
    errors.add(:cash_journal, "must be a cash journal") unless cash_journal.cash?
  end

  def self.filter_by(q)
    rel = matching(status: q[:status])
            .between(:invoice_date, q[:from], q[:to])
    rel = rel.joins(:partner).search(q[:q], "accounting_invoices.invoice_number", "accounting_partners.name", "accounting_invoices.description") if q[:q].present?
    rel = rel.posted if q[:unpaid] == "1"
    rel = rel.posted.where(due_date: ...Date.current) if q[:overdue] == "1"
    rel
  end
end

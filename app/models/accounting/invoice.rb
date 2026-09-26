class Accounting::Invoice < ApplicationRecord
  self.table_name = "accounting_invoices"

  acts_as_tenant :entity
  broadcasts_refreshes_to ->(r) { [ r.entity, :invoices ] }

  include AASM
  include Accounting::MonetaryPrecision
  include Accounting::FiscalYearScoped

  enum :invoice_type,   { customer: 0, supplier: 1 }
  enum :document_type,  { invoice: 0, credit_note: 1 }
  enum :status,         { draft: 0, posted: 1, paid: 2, cancelled: 3, partially_paid: 4 }
  enum :peppol_status,  { not_sent: 0, queued: 1, delivered: 2, failed: 3 }
  enum :vat_treatment,  { domestic: 0, intracom_goods: 1, intracom_services: 2,
                          construction_reverse_charge: 3, export: 4, exempt: 5 }

  # Treatments where VAT is not invoiced to the partner: either self-assessed by
  # the buyer (reverse charge) or genuinely not due (export, exempt).
  REVERSE_CHARGE_TREATMENTS = %w[intracom_goods intracom_services construction_reverse_charge].freeze

  belongs_to :partner,       class_name: "Accounting::Partner"
  belongs_to :credited_invoice, class_name: "Accounting::Invoice", optional: true
  belongs_to :recurring_invoice, class_name: "Accounting::RecurringInvoice", optional: true
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true
  belongs_to :journal,       class_name: "Accounting::Journal", optional: true
  belongs_to :cash_journal,  class_name: "Accounting::Journal", optional: true
  has_many   :credit_notes,  class_name: "Accounting::Invoice", foreign_key: :credited_invoice_id,
                             inverse_of: :credited_invoice, dependent: :restrict_with_error
  has_many   :payment_reminder_items, class_name: "Accounting::PaymentReminderItem", dependent: :restrict_with_error
  has_many   :payment_reminders, -> { order(created_at: :desc, id: :desc) }, through: :payment_reminder_items
  has_many   :peppol_events, -> { order(occurred_at: :desc) }, class_name: "Accounting::PeppolEvent",
                             foreign_key: :invoice_id, inverse_of: :invoice, dependent: :destroy
  has_many   :emails,        -> { order(created_at: :desc) }, class_name: "Accounting::InvoiceEmail",
                             foreign_key: :invoice_id, inverse_of: :invoice, dependent: :destroy
  has_many   :lines,         class_name: "Accounting::InvoiceLine",
                             foreign_key: :invoice_id, dependent: :destroy,
                             inverse_of: :invoice

  accepts_nested_attributes_for :lines, allow_destroy: true, reject_if: :all_blank

  autofilter_column :invoice_number, sql: "accounting_invoices.invoice_number", type: :string, filter: false
  autofilter_column :journal,        sql: "accounting_journals.code", type: :string, left_joins: :journal
  autofilter_column :partner,        sql: "accounting_partners.name", type: :string, joins: :partner
  autofilter_column :invoice_date,   sql: "accounting_invoices.invoice_date", type: :date
  autofilter_column :total_incl_vat, sql: "accounting_invoices.total_incl_vat", type: :decimal
  autofilter_column :status,         sql: "accounting_invoices.status", type: :enum

  validates :invoice_type, presence: true
  validates :invoice_date, presence: true
  validates :partner,      presence: true
  validates :currency,      inclusion: { in: Accounting::MoneyPresenter::SUPPORTED_CURRENCIES }
  validates :exchange_rate, numericality: { greater_than: 0 }

  before_validation :default_due_date, on: :create
  before_validation :apply_franchise_rules

  validate :journal_matches_invoice_type, if: -> { journal.present? }
  validate :cash_journal_is_cash, if: -> { cash_journal.present? }
  validate :vat_treatment_requires_partner_vat_number, if: -> { REVERSE_CHARGE_TREATMENTS.include?(vat_treatment) }
  validate :credited_invoice_matches, if: -> { credited_invoice_id? || credited_invoice.present? }

  aasm column: :status, enum: true do
    state :draft, initial: true
    state :posted
    state :partially_paid
    state :paid
    state :cancelled

    event :post do
      transitions from: :draft, to: :posted
    end

    event :pay do
      transitions from: %i[posted partially_paid], to: :paid
    end

    event :part_pay do
      transitions from: :posted, to: :partially_paid
    end

    event :release do
      transitions from: :partially_paid, to: :posted
    end

    event :reopen do
      transitions from: :paid, to: :posted
    end

    event :cancel do
      transitions from: %i[draft posted], to: :cancelled
    end
  end

  # A draft credit note mirroring this invoice (lines included); edit the lines for a partial credit.
  def build_credit_note
    credit_notes.build(
      document_type: :credit_note, partner: partner, invoice_type: invoice_type, vat_treatment: vat_treatment,
      currency: currency, exchange_rate: exchange_rate, journal: journal, fiscal_year: fiscal_year,
      invoice_date: Date.current
    ).tap do |note|
      lines.each do |l|
        note.lines.build(description: l.description, account: l.account, quantity: l.quantity,
                         unit_price: l.unit_price, vat_rate: l.vat_rate, position: l.position)
      end
    end
  end

  # Under the VAT franchise a draft is domestic and, when it is a sale, charges no VAT. A supplier invoice keeps the VAT
  # rates the supplier charged (Accounting::Actions::GenerateInvoiceJournalEntry books it as a cost). Posted documents are
  # never touched, so that changing the regime only concerns what is issued afterwards.
  def apply_franchise_rules
    return unless draft? && entity&.franchise?

    self.vat_treatment = :domestic
    lines.each { |line| line.vat_rate = 0 } if customer?
    lines.each(&:compute_amounts)
  end

  def compute_totals
    self.subtotal_excl_vat = lines.sum(&:subtotal_excl_vat)
    self.vat_amount        = lines.sum(&:vat_amount)
    # Non-domestic treatments never charge VAT to the partner (self-assessed,
    # exempt or exported) — only vat_amount is kept, for self-assessment.
    self.total_incl_vat    = domestic? ? lines.sum(&:total_incl_vat) : subtotal_excl_vat
  end

  # EUR-equivalent of total_incl_vat, for comparison against journal entry lines (always EUR).
  def total_incl_vat_eur
    (total_incl_vat * exchange_rate).round(2)
  end

  # Customer receipts credit the receivable through lines linked to the invoice (journal_entry_lines.invoice_id).
  def paid_amount
    Accounting::JournalEntryLine.where(invoice_id: id).sum(:credit)
  end

  # Numbered and not cancelled: posted, partially paid or paid.
  def issued? = posted? || partially_paid? || paid?

  # Posted credit notes count as soon as they exist, applied to the invoice or not.
  def credited_amount
    credit_notes.select(&:issued?).sum(&:total_incl_vat_eur) # in memory: preload :credit_notes in batch callers
  end

  def remaining_amount
    [ total_incl_vat_eur - paid_amount - credited_amount, 0 ].max
  end

  def overpaid_amount
    [ paid_amount - total_incl_vat_eur, 0 ].max
  end

  # The posting entry (belongs_to journal_entry) plus any later entry whose
  # lines reference this invoice (payment/lettering, via journal_entry_lines.invoice_id).
  def related_journal_entries
    Accounting::JournalEntry
      .left_joins(:lines)
      .where("accounting_journal_entries.id = :id OR accounting_journal_entry_lines.invoice_id = :invoice_id",
             id: journal_entry_id, invoice_id: id)
      .distinct
      .order(:entry_date)
      .includes(:journal, lines: :account)
  end

  private

  # No due date typed: the invoice date plus the payment terms of the partner (not for credit notes).
  def default_due_date
    return if due_date.present? || !invoice? || partner.nil? || invoice_date.nil?

    self.due_date = invoice_date + partner.payment_terms_days
  end

  def journal_matches_invoice_type
    expected = customer? ? "sale" : "purchase"
    return if journal.journal_type == expected
    errors.add(:journal, "must be a #{expected} journal")
  end

  def cash_journal_is_cash
    errors.add(:cash_journal, "must be a cash journal") unless cash_journal.cash?
  end

  def credited_invoice_matches
    return errors.add(:credited_invoice, "is only allowed on a credit note") unless credit_note?

    original = credited_invoice
    if original.credit_note? || !(original.posted? || original.paid? || original.partially_paid?)
      errors.add(:credited_invoice, "must be a posted invoice")
    elsif [ original.partner_id, original.invoice_type, original.vat_treatment ] !=
          [ partner_id, invoice_type, vat_treatment ]
      errors.add(:credited_invoice, "must have the same partner, type and VAT treatment")
    end
  end

  def vat_treatment_requires_partner_vat_number
    return if partner&.vat_number.present?
    errors.add(:vat_treatment, "requires the partner to have a VAT number")
  end

  def self.filter_by(q)
    rel = matching(status: q[:status])
            .between(:invoice_date, q[:from], q[:to])
    rel = rel.joins(:partner).search(q[:q], "accounting_invoices.invoice_number", "accounting_partners.name", "accounting_invoices.description") if q[:q].present?
    rel = rel.where(status: %i[posted partially_paid]) if q[:unpaid] == "1"
    rel = rel.where(status: %i[posted partially_paid], due_date: ...Date.current) if q[:overdue] == "1"
    rel
  end
end

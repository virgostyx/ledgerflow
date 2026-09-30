# One payment event of an API-managed invoice. The payload is a snapshot taken when the status moved, so a later
# change (a payment undone) never rewrites what the third party was told.
class Accounting::InvoiceEvent < ApplicationRecord
  self.table_name = "accounting_invoice_events"

  EVENT_TYPES = %w[paid partially_paid payment_reopened].freeze
  # The feed only shows events older than this: a transaction still open could commit an event with a lower id after
  # a reader has moved its cursor past it. ponytail: assumes transactions shorter than this.
  SETTLE_DELAY = 5.seconds

  acts_as_tenant :entity

  belongs_to :invoice, class_name: "Accounting::Invoice"

  validates :event_type, inclusion: { in: EVENT_TYPES }

  scope :visible, -> { where(created_at: ..SETTLE_DELAY.ago) }

  def self.record!(invoice, event_type)
    payload = { external_ref: invoice.external_ref, revision: invoice.revision, invoice_number: invoice.invoice_number,
                currency: invoice.currency, total_incl_vat: invoice.total_incl_vat.to_s("F") }
    payload.merge!(settlement(invoice, event_type)) unless event_type == "payment_reopened"
    create!(invoice: invoice, entity_id: invoice.entity_id, event_type: event_type, occurred_at: Time.current, payload: payload)
  end

  # EUR settled on the invoice's payable line, and the date of the latest settling movement. Allocations (partial
  # payments) first, then the total lettering; without either (a SEPA batch just executed) the whole line, today.
  def self.settlement(invoice, event_type)
    trade = invoice.journal_entry&.lines&.joins(:account)&.find_by(accounting_accounts: { code: Accounting::Actions::PayLetteredInvoices::TRADE_ACCOUNTS })
    total = trade ? trade.debit + trade.credit : invoice.total_incl_vat_eur
    allocations = trade ? Accounting::LineAllocation.touching(trade.id) : Accounting::LineAllocation.none

    if event_type == "partially_paid" && allocations.any?
      amount, paid_on = allocations.sum(:amount), allocations.maximum(:allocated_on)
    else
      amount, paid_on = total, settling_date(trade)
    end
    { amount_eur: amount.to_d.to_s("F"), paid_on: (paid_on || Date.current).iso8601 }
  end

  def self.settling_date(trade)
    return unless trade&.lettering_id

    others = Accounting::JournalEntryLine.where(lettering_id: trade.lettering_id).where.not(id: trade.id)
    Accounting::JournalEntry.where(id: others.select(:journal_entry_id)).maximum(:entry_date)
  end
  private_class_method :settling_date
end

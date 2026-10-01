# One payment event of an API-managed invoice. The payload is a snapshot taken when the status moved, so a later
# change (a payment undone) never rewrites what the third party was told.
class Accounting::InvoiceEvent < ApplicationRecord
  self.table_name = "accounting_invoice_events"

  # posted: the accountant (or the API) booked it. paid / partially_paid / payment_confirmed carry the settlement (value date,
  # bank reference, amounts). payment_confirmed: the bank debit of a payment already made (a SEPA batch) is now reconciled.
  # returned: the accountant sent a draft back to the project manager.
  # received: a Peppol invoice has just arrived, for the third party to take over (see Peppol::ReceiveInvoice).
  EVENT_TYPES = %w[received posted paid partially_paid payment_confirmed payment_reopened returned].freeze
  SETTLEMENT_EVENTS = %w[paid partially_paid payment_confirmed].freeze
  # The feed only shows events older than this: a transaction still open could commit an event with a lower id after
  # a reader has moved its cursor past it. ponytail: assumes transactions shorter than this.
  SETTLE_DELAY = 5.seconds

  acts_as_tenant :entity

  belongs_to :invoice, class_name: "Accounting::Invoice"

  validates :event_type, inclusion: { in: EVENT_TYPES }

  scope :visible, -> { where(created_at: ..SETTLE_DELAY.ago) }

  def self.record!(invoice, event_type, reason: nil)
    payload = { external_ref: invoice.external_ref, revision: invoice.revision, invoice_number: invoice.invoice_number,
                currency: invoice.currency, total_incl_vat: invoice.total_incl_vat.to_s("F") }
    payload[:reason] = reason if reason
    payload.merge!(Accounting::InvoiceSettlement.call(invoice).to_payload) if SETTLEMENT_EVENTS.include?(event_type)
    create!(invoice: invoice, entity_id: invoice.entity_id, event_type: event_type, occurred_at: Time.current, payload: payload)
  end

  # What the project manager needs to recognise a received invoice and take it: who, how much, which order it answers.
  def self.record_received!(invoice)
    partner = invoice.partner
    payload = {
      lf_id: invoice.id, supplier_reference: invoice.supplier_reference,
      supplier: { name: partner.name, vat_number: partner.vat_number },
      invoice_date: invoice.invoice_date&.iso8601, due_date: invoice.due_date&.iso8601, currency: invoice.currency,
      amount_excl_vat: invoice.subtotal_excl_vat.to_s("F"), vat_amount: invoice.vat_amount.to_s("F"),
      total_incl_vat: invoice.total_incl_vat.to_s("F"), order_reference: invoice.order_reference,
      buyer_reference: invoice.buyer_reference, has_pdf: invoice.pdf_document.attached?
    }
    create!(invoice: invoice, entity_id: invoice.entity_id, event_type: "received", occurred_at: Time.current, payload: payload)
  end

  # A bank debit has just been reconciled with an entry: for every paid API invoice that entry settles (a payment batch, or
  # payment lines linked to the invoice), tell the third party the bank facts, unless it already knows them.
  def self.record_confirmations(bank_transaction)
    entry_id = bank_transaction.journal_entry_id
    ids = Accounting::JournalEntryLine.where(journal_entry_id: entry_id).where.not(invoice_id: nil).pluck(:invoice_id)
    ids |= Accounting::PaymentBatchLine.active.joins(:payment_batch).where(accounting_payment_batches: { journal_entry_id: entry_id }).pluck(:invoice_id)
    Accounting::Invoice.external.where(id: ids, status: %i[paid partially_paid]).find_each { |invoice| confirm(invoice) }
  end

  def self.confirm(invoice)
    current = Accounting::InvoiceSettlement.call(invoice).to_payload[:settlements].as_json
    last    = where(invoice_id: invoice.id, event_type: SETTLEMENT_EVENTS).order(:id).last
    record!(invoice, "payment_confirmed") unless last && last.payload["settlements"] == current
  end
  private_class_method :confirm
end

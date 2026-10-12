# What a payment pays: an invoice, for an amount (all of its rest, or a part). `active` is true while the batch is active and the payment included; the partial unique
# index on it is what keeps an invoice in one active batch at most, even when two people compose batches at the same moment (invariant I16).
class Payments::ItemInvoice < ApplicationRecord
  self.table_name = "payment_item_invoices"

  acts_as_tenant :entity

  belongs_to :item, class_name: "Payments::Item", inverse_of: :item_invoices
  belongs_to :invoice, class_name: "Accounting::Invoice"

  validates :amount, numericality: { other_than: 0 }
  validate :sign_follows_the_document

  before_validation { self.active = item.batch.active? && item.included? if new_record? && item }

  private

  # An invoice is paid (positive); a credit note netted against it is used up (negative).
  def sign_follows_the_document
    return unless invoice && amount

    errors.add(:amount, invoice.credit_note? ? "of a credit note must be negative" : "of an invoice must be positive") if invoice.credit_note? == amount.positive?
  end
end

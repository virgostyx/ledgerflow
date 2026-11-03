# The part of an advance that an invoice settles (see the migration). Created with the invoice by the API (advance_refs), applied when it is posted
# (Accounting::Actions::ApplyAdvances).
class Accounting::AdvanceAllocation < ApplicationRecord
  self.table_name = "accounting_advance_allocations"

  acts_as_tenant :entity

  belongs_to :invoice, class_name: "Accounting::Invoice", inverse_of: :advance_allocations
  belongs_to :advance, class_name: "Accounting::Invoice", inverse_of: :consumptions
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true

  validates :amount, numericality: { greater_than: 0 }
  validate :same_partner_and_currency

  scope :applied, -> { where.not(journal_entry_id: nil) }
  # What counts against an advance: every allocation of an invoice still alive (a draft claims its share too).
  scope :live, -> { joins(:invoice).where.not(accounting_invoices: { status: Accounting::Invoice.statuses[:cancelled] }) }

  def amount_eur = Fx::Convert.to_eur(amount, invoice.exchange_rate)

  private

  def same_partner_and_currency
    return unless invoice && advance

    errors.add(:advance, "must be an advance") unless advance.advance?
    errors.add(:invoice, "must be an invoice") unless invoice.invoice?
    errors.add(:advance, "must have the same partner as the invoice") unless advance.partner_id == invoice.partner_id
    errors.add(:advance, "must be in the same currency as the invoice") unless advance.currency == invoice.currency
    errors.add(:advance, "must be posted") unless advance.issued?
    errors.add(:amount, "exceeds what is left of the advance (#{advance.advance_remaining_excluding(self)})") if amount && amount > advance.advance_remaining_excluding(self)
  end
end

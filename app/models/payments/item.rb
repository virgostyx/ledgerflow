# One payment of a batch (B01b): to one supplier, with a snapshot of the account paid (the IBAN encrypted) so that the file says what the batch was made with, whatever
# happens to the supplier's file afterwards. It pays one or several invoices, or a part of one.
class Payments::Item < ApplicationRecord
  self.table_name = "payment_items"

  acts_as_tenant :entity

  encrypts :iban

  enum :status, { included: 0, excluded: 1, confirmed: 2, rejected: 3, returned: 4 }

  belongs_to :batch, class_name: "Payments::Batch", inverse_of: :items
  belongs_to :partner, class_name: "Accounting::Partner"
  belongs_to :partner_bank_account, class_name: "Accounting::PartnerBankAccount", optional: true
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true
  has_many :item_invoices, class_name: "Payments::ItemInvoice", foreign_key: :item_id, inverse_of: :item, dependent: :destroy

  validates :iban, :holder_name, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :end_to_end_id, presence: true, length: { maximum: 35 }

  # The payment as it is in the file: what is paid, to whom and with which words, never changes once the batch was exported. Its status does (it is paid, rejected, returned).
  FROZEN = %w[partner_id partner_bank_account_id iban bic holder_name amount currency end_to_end_id remittance structured_remittance].freeze

  validate :frozen_once_exported, on: :update
  before_destroy { throw :abort if batch.exported_file? }
  after_update :hold_or_free_invoices, if: :saved_change_to_status?

  def masked_iban = Accounting::PartnerBankAccount.new(iban: iban).masked_iban

  private

  def frozen_once_exported
    errors.add(:base, "The batch was exported: its payments cannot be changed.") if batch.exported_file? && (changed & FROZEN).any?
  end

  # An excluded payment does not hold its invoices.
  def hold_or_free_invoices
    item_invoices.update_all(active: batch.active? && included?)
  end
end

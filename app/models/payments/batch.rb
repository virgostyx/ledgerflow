# A batch of supplier payments (B01b): composed of approved invoices, checked, approved, exported as a file the person loads and authorizes in their own bank.
# Active from the draft to the moment it is paid or given up: the invoices it holds are held by it (Payments::ItemInvoice#active).
class Payments::Batch < ApplicationRecord
  self.table_name = "payment_batches"

  acts_as_tenant :entity

  enum :status, { draft: 0, pending_approval: 1, approved: 2, exported: 3, submitted: 4, debited: 5, partially_rejected: 6, cancelled: 7, cancel_requested: 8 }

  ACTIVE = %w[draft pending_approval approved exported submitted cancel_requested].freeze

  belongs_to :bank_account, class_name: "Accounting::BankAccount"
  belongs_to :bank_profile, class_name: "Payments::BankProfile", optional: true
  belongs_to :document, class_name: "Accounting::Document", optional: true
  belongs_to :prepared_by, class_name: "User", optional: true
  belongs_to :exported_by, class_name: "User", optional: true
  belongs_to :submitted_by, class_name: "User", optional: true
  belongs_to :cancelled_by, class_name: "User", optional: true
  belongs_to :approval_request, class_name: "Approvals::Request", optional: true
  has_many :items, class_name: "Payments::Item", foreign_key: :batch_id, inverse_of: :batch, dependent: :destroy

  validates :reference, presence: true, uniqueness: { scope: :entity_id }
  validates :requested_execution_date, presence: true

  after_update :release_or_hold_invoices, if: :saved_change_to_status?

  def active? = ACTIVE.include?(status)

  private

  # The invoices of its payments are held while the batch is active, and freed when it is paid or given up.
  def release_or_hold_invoices
    Payments::ItemInvoice.where(item_id: items.where(status: :included).select(:id)).update_all(active: active?)
  end
end

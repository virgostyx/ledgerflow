class Accounting::PaymentBatchLine < ApplicationRecord
  self.table_name = "accounting_payment_batch_lines"

  acts_as_tenant :entity

  belongs_to :payment_batch, class_name: "Accounting::PaymentBatch", inverse_of: :lines
  belongs_to :invoice,       class_name: "Accounting::Invoice"

  validates :amount, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { joins(:payment_batch).merge(Accounting::PaymentBatch.where.not(status: :cancelled)) }

  before_update  :ensure_batch_draft
  before_destroy :ensure_batch_draft

  private

  def ensure_batch_draft
    return if payment_batch.draft?
    raise Accounting::ImmutableRecordError,
          "#{self.class.name} ##{id} belongs to a #{payment_batch.status} batch and cannot be modified."
  end
end

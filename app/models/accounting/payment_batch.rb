class Accounting::PaymentBatch < ApplicationRecord
  self.table_name = "accounting_payment_batches"

  acts_as_tenant :entity

  include AASM

  enum :status, { draft: 0, generated: 1, executed: 2, cancelled: 3 }

  belongs_to :bank_account,  class_name: "Accounting::BankAccount"
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true

  before_destroy :ensure_draft

  has_many :lines, class_name: "Accounting::PaymentBatchLine",
                    foreign_key: :payment_batch_id, dependent: :destroy,
                    inverse_of: :payment_batch

  validates :requested_execution_date, presence: true

  aasm column: :status, enum: true do
    state :draft, initial: true
    state :generated
    state :executed
    state :cancelled

    event :generate do
      transitions from: :draft, to: :generated
    end

    event :execute do
      transitions from: :generated, to: :executed
    end

    event :cancel do
      transitions from: %i[draft generated], to: :cancelled
    end
  end

  def destroyable?
    draft?
  end

  private

  def ensure_draft
    return if draft?
    raise Accounting::ImmutableRecordError,
          "#{self.class.name} ##{id} is #{status} and cannot be deleted."
  end
end

class Accounting::BankTransaction < ApplicationRecord
  self.table_name = "accounting_bank_transactions"

  belongs_to :bank_account,  class_name: "Accounting::BankAccount"
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true

  enum :status, { pending: 0, reconciled: 1, ignored: 2 }

  validates :transaction_date, presence: true
  validates :amount,           presence: true

  scope :pending, -> { where(status: :pending) }

  def credit?
    amount.positive?
  end

  def debit?
    amount.negative?
  end
end

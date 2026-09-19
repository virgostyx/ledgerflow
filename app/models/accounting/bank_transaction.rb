class Accounting::BankTransaction < ApplicationRecord
  self.table_name = "accounting_bank_transactions"

  acts_as_tenant :entity

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

  def self.filter_by(q)
    rel = search(q[:q], "description", "reference").between(:transaction_date, q[:from], q[:to])
    rel = rel.where(amount: 0..) if q[:direction] == "credit"
    rel = rel.where(amount: ...0) if q[:direction] == "debit"
    rel
  end
end

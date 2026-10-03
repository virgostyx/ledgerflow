class Accounting::BankTransaction < ApplicationRecord
  self.table_name = "accounting_bank_transactions"

  acts_as_tenant :entity

  belongs_to :bank_account,  class_name: "Accounting::BankAccount"
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true
  belongs_to :statement, class_name: "Accounting::BankStatement", optional: true # set by the statement imports (F02)

  # pending: to deal with (with a suggestion in match_data when the engine found one); matched: a draft payment entry exists,
  # waiting to be validated; reconciled: booked and validated; ignored.
  enum :status, { pending: 0, reconciled: 1, ignored: 2, matched: 3 }

  # The bank facts of a payment become known once its debit is reconciled: API invoices already marked paid (SEPA batch) get
  # a payment_confirmed event. Only entities that use BudgetFlow.
  after_commit :confirm_invoice_payments, on: :update, if: -> { saved_change_to_journal_entry_id? && journal_entry_id.present? }

  validates :transaction_date, presence: true
  validates :amount,           presence: true
  validates :reference,        uniqueness: { scope: :bank_account_id }, allow_nil: true
  validate  :currency_matches_account

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

  private

  def currency_matches_account
    return unless bank_account && currency.present? && currency != bank_account.currency
    errors.add(:currency, "#{currency} does not match the account currency #{bank_account.currency}")
  end

  def confirm_invoice_payments
    Accounting::InvoiceEvent.record_confirmations(self) if entity.budgetflow?
  end
end

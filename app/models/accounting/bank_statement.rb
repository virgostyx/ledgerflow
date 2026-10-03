# One account's statement, imported from a file (F02): its opening and closing balances, checked against the movements
# (integrity) and against the previous statement (chain). A gap never blocks the import: it marks the statement "to review".
class Accounting::BankStatement < ApplicationRecord
  self.table_name = "accounting_bank_statements"

  STATUSES = %w[ok to_review].freeze

  acts_as_tenant :entity

  belongs_to :bank_account, class_name: "Accounting::BankAccount"
  belongs_to :import_batch, class_name: "Accounting::ImportBatch"
  has_many :transactions, class_name: "Accounting::BankTransaction", foreign_key: :statement_id, dependent: :restrict_with_error

  validates :old_balance, presence: true
  validates :status, inclusion: { in: STATUSES }

  def to_review? = status == "to_review"
  def chain_broken? = chain_gap.present? && !chain_gap.zero?
end

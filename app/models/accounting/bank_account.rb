class Accounting::BankAccount < ApplicationRecord
  self.table_name = "accounting_bank_accounts"

  acts_as_tenant :entity

  belongs_to :journal, class_name: "Accounting::Journal"
  has_many :transactions, class_name: "Accounting::BankTransaction",
           foreign_key: :bank_account_id, dependent: :destroy

  validates :label_fr,   presence: true
  validates :iban,       presence: true, uniqueness: { scope: :entity_id }
  validates :currency,   presence: true, inclusion: { in: %w[EUR] }
  validates :journal_id, uniqueness: true, allow_nil: true

  validate :iban_format
  validate :journal_must_be_bank_type

  scope :active, -> { where(active: true) }

  def destroyable?
    transactions.none?
  end

  def balance_from_transactions
    transactions.reconciled.sum(:amount)
  end

  private

  def iban_format
    return if iban.blank?
    errors.add(:iban, :invalid) unless IBANTools::IBAN.valid?(iban)
  end

  def journal_must_be_bank_type
    return unless journal
    errors.add(:journal, "must be of type bank") unless journal.bank?
  end
end

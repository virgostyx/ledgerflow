class Accounting::BankAccount < ApplicationRecord
  self.table_name = "accounting_bank_accounts"

  acts_as_tenant :entity
  broadcasts_refreshes_to ->(r) { [ r.entity, :bank_accounts ] }

  belongs_to :journal, class_name: "Accounting::Journal"
  has_many :transactions, class_name: "Accounting::BankTransaction",
           foreign_key: :bank_account_id, dependent: :destroy

  autofilter_column :journal,  sql: "accounting_journals.code", type: :string, joins: :journal
  autofilter_column :label_fr, sql: "accounting_bank_accounts.label_fr", type: :string, filter: false
  autofilter_column :iban,     sql: "accounting_bank_accounts.iban", type: :string, filter: false
  autofilter_column :bic,      sql: "accounting_bank_accounts.bic", type: :string, filter: false
  autofilter_column :active,   sql: "accounting_bank_accounts.active", type: :boolean

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

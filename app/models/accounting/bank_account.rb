class Accounting::BankAccount < ApplicationRecord
  self.table_name = "accounting_bank_accounts"

  belongs_to :journal,      class_name: "Accounting::Journal"
  has_many   :transactions, class_name: "Accounting::BankTransaction",
                            foreign_key: :bank_account_id,
                            dependent: :destroy

  validates :label_fr, presence: true
  validates :iban,     presence: true, uniqueness: true
  validate  :iban_format

  private

  def iban_format
    return if iban.blank?
    errors.add(:iban, :invalid) unless IBANTools::IBAN.valid?(iban)
  end
end

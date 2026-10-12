# B01b: who sees the bank accounts of the suppliers, who registers one, and who verifies or blocks one. Verifying is not entering: whoever verifies is
# another person than whoever registered (Payments::VerifyBankAccount checks it), and holds `bank_accounts.verify`.
class Accounting::PartnerBankAccountPolicy < ApplicationPolicy
  def index?    = can?("records.list")
  def show?     = can?("records.view")
  def register? = can?("records.write")
  def verify?   = can?("bank_accounts.verify")
  def block?    = can?("bank_accounts.verify")
end

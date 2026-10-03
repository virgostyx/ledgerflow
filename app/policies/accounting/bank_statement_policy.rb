# Bank statements (F02): importing a file is for those who can keep the books, matching a line for those who can reconcile
# (the assistant included: a match produces a draft, never a validated entry).
class Accounting::BankStatementPolicy < ApplicationPolicy
  def index? = can?("reports.view")
  def show?  = can?("reports.view")
  def import? = can?("bank.import")
  def match?  = can?("bank.match")
end

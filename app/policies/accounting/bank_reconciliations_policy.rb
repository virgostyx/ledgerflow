class Accounting::BankReconciliationsPolicy < ApplicationPolicy
  def show?   = can?("reconciliations.manage")
  def update? = can?("reconciliations.manage")
  # Booking a movement validates the payment entry it creates: whoever cannot validate cannot do it (F02 will let them
  # produce drafts instead).
  def post?   = can?("reconciliations.manage") && can?("entries.post")
end

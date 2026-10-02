class Accounting::BankReconciliationsPolicy < ApplicationPolicy
  def show?   = can?("reconciliations.manage")
  def update? = can?("reconciliations.manage")
end

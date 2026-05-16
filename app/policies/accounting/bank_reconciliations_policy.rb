class Accounting::BankReconciliationsPolicy < ApplicationPolicy
  def show?   = user.admin? || user.accountant?
  def update? = user.admin? || user.accountant?
end

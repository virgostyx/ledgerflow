class Accounting::BankReconciliationsPolicy < ApplicationPolicy
  def show?   = entity_accountant?
  def update? = entity_accountant?
end

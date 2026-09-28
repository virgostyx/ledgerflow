class Accounting::AccrualPolicy < ApplicationPolicy
  def index? = entity_accountant?
  def book? = create?
  def reverse? = create?
  def destroy? = create?
end

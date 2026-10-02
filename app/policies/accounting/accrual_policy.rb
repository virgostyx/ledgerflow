class Accounting::AccrualPolicy < ApplicationPolicy
  def index? = can?("closing.adjust")
  def book? = create?
  def reverse? = create?
  def destroy? = create?
end

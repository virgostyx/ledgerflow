class Accounting::PeriodLockPolicy < ApplicationPolicy
  def create? = can?("periods.lock")
  def new?    = create?
  def unlock? = can?("periods.unlock")
end

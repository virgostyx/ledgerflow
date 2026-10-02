class Accounting::AuditLogPolicy < ApplicationPolicy
  def index? = can?("audit.view")
  def show? = can?("audit.view")
end

class Accounting::AuditLogPolicy < ApplicationPolicy
  def index? = entity_auditor?
  def show? = entity_auditor?
end

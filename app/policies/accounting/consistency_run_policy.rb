class Accounting::ConsistencyRunPolicy < ApplicationPolicy
  def index? = entity_auditor?
  def create? = entity_accountant?
  def acknowledge? = entity_accountant?
end

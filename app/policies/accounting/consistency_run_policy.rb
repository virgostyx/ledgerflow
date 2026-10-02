class Accounting::ConsistencyRunPolicy < ApplicationPolicy
  def index? = can?("audit.view")
  def create? = can?("closing.adjust")
  def acknowledge? = can?("closing.adjust")
end

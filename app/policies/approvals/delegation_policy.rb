# B01a: delegations are visible to every owner, and made by the owner.
class Approvals::DelegationPolicy < ApplicationPolicy
  def index?   = can?("approvals.configure")
  def create?  = can?("approvals.configure")
  def destroy? = can?("approvals.configure")
end

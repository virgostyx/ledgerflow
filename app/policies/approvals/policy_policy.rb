# B01a: the approval policies are the owner's to write.
class Approvals::PolicyPolicy < ApplicationPolicy
  def index?   = can?("approvals.configure")
  def create?  = can?("approvals.configure")
  def update?  = can?("approvals.configure")
  def destroy? = can?("approvals.configure")
end

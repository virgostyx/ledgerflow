# B01a: looking at what waits for approval and deciding on it. Having the right is not enough to decide on a given request:
# the circuit names the approvers (Approvals::Decide).
class Approvals::RequestPolicy < ApplicationPolicy
  def index?   = can?("approvals.approve")
  def show?    = can?("approvals.approve")
  def approve? = can?("approvals.approve")
  def decide?  = can?("approvals.approve")
  def bulk?    = can?("approvals.approve")

  # The figures of the approvals, by approver and by supplier: for those who may see the audit trail (who did what is its business).
  def statistics? = can?("audit.view")
end

# B01a: looking at what waits for approval and deciding on it. Having the right is not enough to decide on a given request:
# the circuit names the approvers (Approvals::Decide).
class Approvals::RequestPolicy < ApplicationPolicy
  def index?   = can?("approvals.approve")
  def approve? = can?("approvals.approve")
end

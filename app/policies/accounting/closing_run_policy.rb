# The guided closing of a fiscal year (F10): seen by whoever sees the records, run by those who prepare it (`closing.prepare`), approved, and a closed
# year reopened, by the owner alone (`closing.approve`).
class Accounting::ClosingRunPolicy < ApplicationPolicy
  def index?   = can?("records.view")
  def show?    = can?("records.view")
  def create?  = can?("closing.prepare")
  def update?  = can?("closing.prepare")
  def approve? = can?("closing.approve")
  def reopen?  = can?("closing.approve")
end

# Consolidation of a group (F12b): read with `consolidation.view`, prepared with `consolidation.run`, validated and frozen with `consolidation.approve`, all in the
# parent company. And one more condition that no role can lift: the person must have access to EVERY member company (Consolidation::Access), otherwise
# the consolidation is refused whole, never partial.
class Accounting::ConsolidationPolicy < ApplicationPolicy
  def index?   = can?("consolidation.view")
  def show?    = can?("consolidation.view")
  def create?  = can?("consolidation.run")
  def update?  = can?("consolidation.run")
  def approve? = can?("consolidation.approve")
end

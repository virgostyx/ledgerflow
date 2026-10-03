class Accounting::LetteringPolicy < ApplicationPolicy
  def destroy? = create?
  def cross_partner? = can?("reconciliations.cross_partner")
  def unreconcile_locked? = can?("reconciliations.unreconcile_locked")
end

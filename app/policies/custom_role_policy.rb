# The roles an owner composes (F01): the owners only, like the accesses themselves.
class CustomRolePolicy < ApplicationPolicy
  def index?   = can?("users.manage")
  def create?  = can?("users.manage")
  def update?  = can?("users.manage")
  def destroy? = can?("users.manage")
end

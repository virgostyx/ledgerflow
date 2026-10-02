# Who has access to the entity, with which role (F01): the owners' call.
class UserEntityPolicy < ApplicationPolicy
  def index?  = can?("users.manage")
  def create? = can?("users.manage")
  def update? = can?("users.manage")
end

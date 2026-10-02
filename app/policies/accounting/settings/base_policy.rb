class Accounting::Settings::BasePolicy < ApplicationPolicy
  def index?   = can?("settings.manage")
  def show?    = index?
  def new?     = index?
  def create?  = index?
  def edit?    = index?
  def update?  = index?
  def destroy? = can?("records.delete")

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end

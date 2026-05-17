class Accounting::Settings::BasePolicy < ApplicationPolicy
  def index?   = user.admin? || user.accountant?
  def show?    = index?
  def new?     = index?
  def create?  = index?
  def edit?    = index?
  def update?  = index?
  def destroy? = user.admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end

class Accounting::Settings::BasePolicy < ApplicationPolicy
  def index?   = entity_accountant?
  def show?    = index?
  def new?     = index?
  def create?  = index?
  def edit?    = index?
  def update?  = index?
  def destroy? = entity_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end

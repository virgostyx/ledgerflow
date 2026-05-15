class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user   = user
    @record = record
  end

  def index?   = user.admin? || user.accountant? || user.manager?
  def show?    = index?
  def create?  = user.admin? || user.accountant?
  def new?     = create?
  def update?  = user.admin? || user.accountant?
  def edit?    = update?
  def destroy? = user.admin?

  class Scope
    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve = scope.all

    private

    attr_reader :user, :scope
  end
end

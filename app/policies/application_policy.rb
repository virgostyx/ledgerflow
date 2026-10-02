class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user   = user
    @record = record
  end

  def index?   = can?("records.list")
  def show?    = can?("records.view")
  def create?  = can?("records.write")
  def new?     = create?
  def update?  = can?("records.write")
  def edit?    = update?
  def destroy? = can?("records.delete")

  class Scope
    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve = scope.all

    private

    attr_reader :user, :scope
  end

  private

  def current_entity
    ActsAsTenant.current_tenant
  end

  def membership
    @membership ||= UserEntity.find_by(user: user, entity: current_entity, active: true)
  end

  def can?(permission) = Permissions.allowed?(membership&.role, permission)
end

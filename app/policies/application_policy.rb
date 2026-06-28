class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user   = user
    @record = record
  end

  def index?   = entity_manager?
  def show?    = entity_any_member?
  def create?  = entity_accountant?
  def new?     = create?
  def update?  = entity_accountant?
  def edit?    = update?
  def destroy? = entity_admin?

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

  def entity_admin?      = membership&.admin?
  def entity_accountant? = entity_admin? || membership&.accountant?
  def entity_manager?    = entity_accountant? || membership&.manager?
  def entity_auditor?    = entity_manager? || membership&.auditor?
  def entity_any_member? = membership.present?
end

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

    # The records of the journals the access is limited to (all of them when it is not).
    def in_allowed_journals
      allowed = UserEntity.current.find_by(user: user, entity: ActsAsTenant.current_tenant)&.journal_ids
      allowed ? scope.where(journal_id: allowed) : scope.all
    end

    private

    attr_reader :user, :scope
  end

  private

  def current_entity
    ActsAsTenant.current_tenant
  end

  def membership
    @membership ||= UserEntity.current.find_by(user: user, entity: current_entity)
  end

  def can?(permission) = membership ? membership.allows?(permission) : Permissions.allowed?(nil, permission)

  # F01: an access limited to some journals reaches only the records of those. A record without a journal (the empty
  # form, a class) is not concerned.
  def journal_allowed? = !record.respond_to?(:journal_id) || record.journal_id.nil? || membership&.allows_journal?(record.journal_id) == true

  # Exporting: always for the roles that write, and for the read-only roles only when the entity allows it.
  def can_export? = can?("reports.export") || (can?("reports.export_readonly") && current_entity&.read_only_export? == true)
end

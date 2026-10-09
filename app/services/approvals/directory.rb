# Who is who in the entity the circuit works in, read once (B01a): the memberships of THIS entity that give access today, with their rights, and the
# delegations in force. Every question the circuit asks about people goes through here, so that nothing looks outside the entity (UserEntity is not
# scoped to it by itself: an access held in another company counts for nothing here) and nothing asks the database once per request.
class Approvals::Directory
  attr_reader :entity

  def initialize(entity = ActsAsTenant.current_tenant)
    @entity = entity
    @memberships = UserEntity.current.where(entity_id: entity.id).includes(:custom_role).to_a
    @delegations = Approvals::Delegation.in_force_on(Date.current).to_a
  end

  def member?(user_id) = by_user.key?(user_id)

  def role_of(user_id) = by_user[user_id]&.role

  # Holders of `approvals.approve` here, by their system role or their custom role.
  def approving_ids = @approving_ids ||= @memberships.select { |m| m.allows?("approvals.approve") }.map(&:user_id).to_set

  def approving?(user_id) = approving_ids.include?(user_id)

  def owner_ids = @memberships.select(&:owner?).map(&:user_id)

  # The people who hold one of these roles as their system role (an access with a custom role has its own set of rights, not a role).
  def ids_with_role(roles) = roles.empty? ? [] : @memberships.select { |m| m.custom_role_id.nil? && roles.include?(m.role) }.map(&:user_id)

  # { delegate_id => delegator_id } for the delegations in force from one of these people, covering this policy.
  def delegates_of(principal_ids, policy_id)
    @delegations.select { |d| principal_ids.include?(d.delegator_id) && (d.policy_ids.blank? || d.policy_ids.include?(policy_id)) }.to_h { |d| [ d.delegate_id, d.delegator_id ] }
  end

  # The memberships that asked for e-mail, with a user.
  def mailable = @memberships.select(&:notify_by_email)

  private

  def by_user = @by_user ||= @memberships.index_by(&:user_id)
end

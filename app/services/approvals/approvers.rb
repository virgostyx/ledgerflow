# Who may decide on the current step of a request (B01a): the people and the roles the step names, and whoever stands in
# for one of them today. A delegation is one hop (a delegate's own delegates do not count) and may name the policies it covers.
# Everybody must hold `approvals.approve` in the entity as of today.
# => { user_id => on_behalf_of_user_id (nil when they decide for themselves) }
class Approvals::Approvers
  def self.for(request)
    step = request.policy&.steps&.find_by(position: request.current_step)
    return {} unless step

    principals = principal_ids(step) | called_in(request)
    direct = principals.index_with { nil }
    delegated = Approvals::Delegation.in_force_on(Date.current).where(delegator_id: principals)
                                     .select { |d| d.policy_ids.blank? || d.policy_ids.include?(request.policy_id) }
                                     .to_h { |d| [ d.delegate_id, d.delegator_id ] }
    allowed = approving_user_ids((direct.keys + delegated.keys).uniq)
    delegated.merge(direct).slice(*allowed) # deciding for oneself wins over deciding for someone
  end

  # Who the timers called in: the person named for the escalation, and the owners once it went to them or the request was rerouted.
  def self.called_in(request)
    ids = [ request.escalated_to_id ].compact
    ids += UserEntity.owners.current.pluck(:user_id) if request.rerouted_at || (request.escalated_at && request.escalated_to_id.nil?)
    ids
  end

  # The people the step names, directly or through a role.
  def self.principal_ids(step)
    by_role = step.approver_roles.empty? ? [] : UserEntity.current.where(role: step.approver_roles, custom_role_id: nil).pluck(:user_id)
    (step.approver_user_ids + by_role).uniq
  end

  def self.approving_user_ids(user_ids)
    UserEntity.current.includes(:custom_role).where(user_id: user_ids).select { |membership| membership.allows?("approvals.approve") }.map(&:user_id)
  end
  private_class_method :approving_user_ids, :called_in
end

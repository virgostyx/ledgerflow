# Who may decide on the current step of a request (B01a): the people and the roles the step names, those the timers called in, and whoever stands
# in for one of them today. A delegation is one hop (a delegate's own delegates do not count) and may name the policies it covers.
# Everybody must hold `approvals.approve` in THIS entity as of today (see Approvals::Directory: nothing is read outside it).
# Pass a directory to ask about many requests at once: it is read once. => { user_id => on_behalf_of_user_id (nil when they decide for themselves) }
class Approvals::Approvers
  def self.for(request, directory = Approvals::Directory.new(request.entity))
    step = request.policy&.steps&.detect { |s| s.position == request.current_step }
    return {} unless step

    principals = (step.approver_user_ids + directory.ids_with_role(step.approver_roles) + called_in(request, directory)).uniq
    direct = principals.index_with { nil }
    delegated = directory.delegates_of(principals, request.policy_id)
    allowed = (direct.keys + delegated.keys).uniq.select { |id| directory.approving?(id) }
    delegated.merge(direct).slice(*allowed) # deciding for oneself wins over deciding for someone
  end

  # Who the timers called in: the person named for the escalation, and the owners once it went to them or the request was rerouted.
  def self.called_in(request, directory)
    ids = [ request.escalated_to_id ].compact
    ids += directory.owner_ids if request.rerouted_at || (request.escalated_at && request.escalated_to_id.nil?)
    ids
  end
  private_class_method :called_in
end

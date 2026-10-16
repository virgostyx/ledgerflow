# B02c: where the approval of a publication stands, from the decisions that still count. A decision counts if it is active (not superseded by a newer version) and its author still qualifies
# (a director with the right and a verified identity): a director who was replaced no longer counts, and the new one must be verified first. Policy "one": a single approval is enough; "all":
# every approver. One who approves and one who refuses: disputed, it waits and the firm is told.
# => { state: :not_required | :superseded | :blocked | :pending | :approved | :refused | :disputed, waiting_for: [portal user ids], problem: }
class PortalAdmin::ApprovalStatus
  def self.call(publication)
    return { state: :not_required } unless publication.requires_approval?
    return { state: :superseded } if publication.replaced_by_id

    qualifying = publication.approvers.to_a.select { |person| person.qualified_approver_in?(publication.entity_id) }
    return { state: :blocked, problem: "No approver holds the right to approve with a verified identity: verify the identity of the new director and publish again." } if qualifying.empty?

    decisions = publication.approvals.active.where(portal_user_id: qualifying.map(&:id)).to_a
    refused, approving = decisions.partition { |d| d.decision == "refused" }
    waiting = qualifying.map(&:id) - decisions.map(&:portal_user_id)
    state = if refused.any? && approving.any? then :disputed
    elsif refused.any? then :refused
    elsif publication.approvals_required == "all" ? waiting.empty? : approving.any? then :approved
    else :pending
    end
    { state: state, waiting_for: waiting }
  end
end

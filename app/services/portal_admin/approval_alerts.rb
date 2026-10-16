# B02c: tells the firm, once, when two approvers of a publication disagree (one approves, one refuses): the publication stays pending until the firm acts.
class PortalAdmin::ApprovalAlerts
  def self.call
    Portal::Publication.visible.where(requires_approval: true).find_each do |publication|
      next unless PortalAdmin::ApprovalStatus.call(publication)[:state] == :disputed

      ActsAsTenant.with_tenant(Entity.find(publication.entity_id)) do
        Accounting::Notify.call(user: publication.published_by, event: "portal_decision_disputed", subject: publication, data: { message: publication.title })
      end
    end
  end
end

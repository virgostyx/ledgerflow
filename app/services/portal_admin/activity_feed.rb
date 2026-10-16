# B02a: the events of the portal that concern a company: those tied to it, and the sign-ins (tied to none) of the people who have a right in it.
class PortalAdmin::ActivityFeed
  def self.call(entity:)
    members = Portal::Grant.where(entity_id: entity.id).select(:portal_user_id)
    Portal::Event.where(entity_id: entity.id).or(Portal::Event.where(entity_id: nil, portal_user_id: members))
  end
end

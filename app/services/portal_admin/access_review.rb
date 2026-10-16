# B02a: the quarterly review of the accesses of a company: every right in force, the last time it was used, and those not used for 90 days flagged.
class PortalAdmin::AccessReview
  INACTIVE_AFTER = 90.days
  Row = Struct.new(:grant, :portal_user, :last_access, :inactive, keyword_init: true)

  def self.call(entity:)
    Portal::Grant.in_force.where(entity_id: entity.id).includes(:portal_user).order(:created_at).map do |grant|
      person = grant.portal_user
      last = person.last_seen_at || person.last_sign_in_at
      Row.new(grant: grant, portal_user: person, last_access: last, inactive: (last || grant.created_at) < INACTIVE_AFTER.ago)
    end
  end
end

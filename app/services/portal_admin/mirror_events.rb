# B02a: copies what the people of the portal did into the audit trail of the companies (R18), with actor_type portal_user. The portal itself never writes to the trail.
# An event of a company goes to that company; one with no company (a sign-in) goes to each company where the person has a right; one that no company can claim (an unknown
# address) is marked done, as the trail is per company. A company where the portal was turned off keeps its events for later.
class PortalAdmin::MirrorEvents
  BATCH = 500

  def self.call
    Portal::Event.where(mirrored_at: nil).order(:id).limit(BATCH).includes(:portal_user).each { |event| mirror(event) }
  end

  def self.mirror(event)
    entities = companies_of(event)
    return event.update_columns(mirrored_at: Time.current) if entities.empty? && event.entity_id.nil?
    return if entities.empty? # the company is gone or turned the portal off

    entities.each do |entity|
      ActsAsTenant.with_tenant(entity) do
        Accounting::AuditLog.record!(auditable: event.portal_user || entity, action: "portal_#{event.action}", actor_type: "portal_user", ip_address: event.ip_address,
                                     payload: { portal_user_id: event.portal_user_id, email: event.portal_user&.email || event.email_tried, target: event.target_token, event_id: event.id, at: event.occurred_at.utc.iso8601(6) }.merge(event.metadata.symbolize_keys).compact)
      end
    end
    event.update_columns(mirrored_at: Time.current)
  end

  def self.companies_of(event)
    ids = event.entity_id ? [ event.entity_id ] : (event.portal_user ? event.portal_user.grants.pluck(:entity_id).uniq : [])
    Entity.where(id: ids).select { |entity| entity.feature?(:b02a) }
  end
  private_class_method :mirror, :companies_of
end

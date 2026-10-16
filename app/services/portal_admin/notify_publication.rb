# B02a: tells, at once, the people who may see a new publication and asked for it. A mail that cannot be sent never fails the publication.
class PortalAdmin::NotifyPublication
  def self.call(publication)
    company = Portal::Company.find(publication.entity_id)
    people_for(publication).where(notification_frequency: "immediate").find_each do |person|
      Portal::NotificationMailer.new_publications(person, company.name, 1).deliver_now
    rescue StandardError => e
      Rails.logger.error("portal notification not sent: #{e.class}")
    end
  end

  # Whoever has a right in force that lists publications.view in this company, active, and is addressed (all if the publication names no one).
  def self.people_for(publication)
    granted = Portal::Grant.in_force.where(entity_id: publication.entity_id).where("capabilities @> ?", [ "publications.view" ].to_json).select(:portal_user_id)
    people = PortalUser.active.where(id: granted)
    publication.recipient_rows.exists? ? people.where(id: publication.recipient_rows.select(:portal_user_id)) : people
  end
end

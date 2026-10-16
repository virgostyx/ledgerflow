# B02c: tells the people of a company's portal that the firm wrote in the thread: a count and a link, never the text. A message that cannot be sent never fails the answer.
class PortalAdmin::NotifyMessage
  def self.call(entity)
    granted = Portal::Grant.in_force.where(entity_id: entity.id).where("capabilities @> ?", [ "messages.use" ].to_json).select(:portal_user_id)
    PortalUser.active.where(id: granted).where.not(notification_frequency: "off").find_each do |person|
      Portal::NotificationMailer.new_message(person, entity.name).deliver_now
    rescue StandardError => e
      Rails.logger.error("portal notification not sent: #{e.class}")
    end
  end
end

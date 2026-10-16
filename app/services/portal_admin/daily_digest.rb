# B02a: one mail a day, per company, to those who asked for a digest and have something new since the last one.
class PortalAdmin::DailyDigest
  def self.call
    PortalUser.active.where(notification_frequency: "daily").find_each do |person|
      since = person.last_digest_at || 1.day.ago
      counts = Portal::Publication.in_reach_of(person).visible.where("published_at > ?", since).group(:entity_id).count
      counts.each do |entity_id, count|
        Portal::NotificationMailer.new_publications(person, Portal::Company.find(entity_id).name, count).deliver_now
      rescue StandardError => e
        Rails.logger.error("portal digest not sent: #{e.class}")
      end
      person.update_columns(last_digest_at: Time.current)
    end
  end
end

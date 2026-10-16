# B02b: the reminder of the requests for supporting documents, every morning: when the date asked is within three days or past and a line is still open, the clients who may see the lines are
# told how many are waiting (not which), at most every three days.
class PortalAdmin::RemindDocumentRequests
  EVERY = 3.days

  def self.call(today: Date.current)
    Portal::DocumentRequest.where("due_on <= ?", today + 3).where("last_reminder_on IS NULL OR last_reminder_on <= ?", today - EVERY.in_days.to_i).includes(:company).find_each do |request|
      open = request.lines.open_ones.count
      next if open.zero?

      PortalAdmin::RequestDocuments.people(request.company).each do |person|
        next if person.notification_frequency == "off"

        Portal::NotificationMailer.documents_requested(person, request.company.name, open).deliver_now
      rescue StandardError => e
        Rails.logger.error("portal reminder not sent: #{e.class}")
      end
      request.update!(last_reminder_on: today)
    end
  end
end

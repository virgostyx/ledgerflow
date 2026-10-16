# B02c: the weekly e-mail to the people of the portal: how many questions wait for them, how many documents are asked, how many publications await their approval, with a link. Counters only:
# no title, no label, no amount. Nothing is sent when nothing waits, nor to someone who chose not to be told.
class PortalAdmin::WeeklySummary
  def self.call
    PortalUser.active.where.not(notification_frequency: "off").find_each do |person|
      counts = counts_for(person)
      next if counts.values.sum.zero?

      Portal::NotificationMailer.weekly_summary(person, counts).deliver_now
    rescue StandardError => e
      Rails.logger.error("portal summary not sent: #{e.class}")
    end
  end

  def self.counts_for(person)
    {
      questions: Portal::Question.in_reach_of(person).open.count,
      documents: Portal::DocumentRequestLine.in_reach_of(person).open_ones.count,
      approvals: Portal::Publication.in_reach_of(person).visible.where(requires_approval: true).select { |p| p.approver?(person) && person.qualified_approver_in?(p.entity_id) && !p.approvals.active.exists?(portal_user_id: person.id) }.size
    }
  end
  private_class_method :counts_for
end

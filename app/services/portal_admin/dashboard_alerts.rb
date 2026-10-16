# B02c: the alerts the firm defined: the forecast cash (R14, thirteen weeks, base scenario) goes under a threshold. The directors of the company's portal are told that there is something to
# look at (never an amount), at most once a week per rule.
class PortalAdmin::DashboardAlerts
  EVERY = 7

  def self.call(today: Date.current)
    Portal::AlertRule.where(active: true).includes(:company).find_each do |rule|
      next if rule.last_alerted_on && rule.last_alerted_on > today - EVERY

      entity = Entity.find(rule.entity_id)
      next unless entity.feature?(:b02a) && entity.feature?(:b02c)
      next unless ActsAsTenant.with_tenant(entity) { low?(rule) }

      directors(entity).each { |person| tell(person, entity) }
      rule.update!(last_alerted_on: today)
    end
  end

  def self.low?(rule) = Accounting::CashForecastQuery.new(horizon: :weeks_13, threshold: rule.threshold).call.weeks.any?(&:alert)

  def self.directors(entity)
    granted = Portal::Grant.in_force.where(entity_id: entity.id, role: "director").where("capabilities @> ?", [ "dashboard.view" ].to_json).select(:portal_user_id)
    PortalUser.active.where(id: granted).where.not(notification_frequency: "off")
  end

  def self.tell(person, entity)
    Portal::NotificationMailer.dashboard_alert(person, entity.name).deliver_now
  rescue StandardError => e
    Rails.logger.error("portal alert not sent: #{e.class}")
  end
  private_class_method :low?, :directors, :tell
end

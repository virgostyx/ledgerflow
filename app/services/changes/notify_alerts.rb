# B03b: once a day, tells each subscriber how many alerts of the kinds they follow arose since they were last told. A count and a link: no amount, no name (the least detail).
# One notification a day per person (the event carries the date), and only to who may still review the changes.
class Changes::NotifyAlerts
  FIRST_LOOK_BACK = 1.day

  def self.call
    Entity.where(active: true).find_each do |entity|
      next unless entity.feature?(:b03a) && entity.feature?(:b03b)

      ActsAsTenant.with_tenant(entity) { new(entity).call }
    end
  end

  def initialize(entity) = @entity = entity

  def call
    now = Time.current
    Accounting::ChangeSubscription.includes(:user).find_each do |subscription|
      since = subscription.last_notified_at || now - FIRST_LOOK_BACK
      tell(subscription, since, now)
      subscription.update_columns(last_notified_at: now)
    end
  end

  private

  def tell(subscription, since, now)
    return unless Accounting::ChangesPolicy.new(subscription.user, :changes).review? && member?(subscription.user)

    report = Changes::Report.call(fiscal_year: Accounting::FiscalYear.current, from: [ since, history_start ].max, to: now, per: 1, statements: false, show_authors: false)
    counts = report.alerts.map(&:kind).map(&:to_s).tally.slice(*subscription.kinds)
    return if counts.empty?

    Accounting::Notify.call(user: subscription.user, event: "changes_alerts:#{now.to_date}", subject: subscription,
                            data: { message: counts.map { |kind, n| I18n.t("changes.notification.#{kind}", count: n) }.to_sentence, from: since.utc.iso8601(6) })
  end

  def history_start = Accounting::KnownAt.new(Time.current, fiscal_year: Accounting::FiscalYear.current).history_start

  def member?(user) = UserEntity.current.exists?(user_id: user.id, entity_id: @entity.id)
end

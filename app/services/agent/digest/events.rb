# The alerts that do not wait for the morning (A10a): a new blocking anomaly, a cash forecast under the threshold, a VAT return due in five days, a fiscal year about to end with drafts left. Each is told at most
# once per type and per day to a person who turned the summary on, with the rights of that person. They are the urgent items of the same sources, nothing else.
module Agent::Digest::Events
  SOURCES = {
    "blocking_anomaly" => ->(item) { item.key == "anomalies" && item.urgent },
    "cash_below_threshold" => ->(item) { item.key == "cash" },
    "vat_due" => ->(item) { item.key == "vat" && item.urgent },
    "period_with_drafts" => ->(item) { item.key == "closing" && item.urgent }
  }.freeze

  # => the digests built now (each one a notification to deliver).
  def self.check(user:, entity:, today: Date.current)
    SOURCES.keys.filter_map do |event|
      next if ActsAsTenant.with_tenant(entity) { Agent::Digest.exists?(user_id: user.id, kind: "event", event_type: event, local_date: today) }

      Agent::Digest::Build.call(user: user, entity: entity, today: today, event: event)
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end

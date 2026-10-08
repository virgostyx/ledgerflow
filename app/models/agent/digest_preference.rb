# When, how and about what a person wants their summary (A10a): off until they turn it on, daily or weekly, at an hour of their time zone, in the sections they choose among those their rights give, with an
# e-mail if they want one. The entity decides whether the e-mail may carry details (Agent::Setting#digest_email_details).
class Agent::DigestPreference < ApplicationRecord
  self.table_name = "agent_digest_preferences"

  FREQUENCIES = %w[daily weekly].freeze

  acts_as_tenant :entity

  belongs_to :user

  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :weekday, inclusion: { in: 0..6 }
  validates :send_hour, inclusion: { in: 0..23 }
  validates :time_zone, inclusion: { in: ->(_) { ActiveSupport::TimeZone.all.map { |zone| zone.tzinfo.name } } }
  validates :user_id, uniqueness: { scope: :entity_id }

  def self.for(user) = find_or_initialize_by(user: user)

  def zone = ActiveSupport::TimeZone[time_zone]

  # Whether a summary is due now: the hour of the person has come, on their weekday for a weekly one, and none was built since this hour began.
  def due?(now = Time.current)
    local = now.in_time_zone(zone)
    return false unless enabled? && local.hour >= send_hour
    return false if frequency == "weekly" && local.wday != weekday

    last_built_at.nil? || last_built_at.in_time_zone(zone).to_date < local.to_date
  end
end

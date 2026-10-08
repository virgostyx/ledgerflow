# Every hour (A10a): builds the summary of each person whose hour has come, in their time zone, at their frequency, and looks for the alerts of the day. A summary with nothing to say is not made. The reading of
# the facts uses no model; this job never calls one.
class Agent::DigestJob < ApplicationJob
  queue_as :agent_batch

  def perform(now = Time.current)
    ActsAsTenant.without_tenant do
      Agent::DigestPreference.where(enabled: true).includes(:user, :entity).find_each do |preference|
        entity, user = preference.entity, preference.user
        next unless ActsAsTenant.with_tenant(entity) { Agent::Access.check(Agent::Context.build(user: user, entity: entity, locale: :en)).nil? }

        today = now.in_time_zone(preference.zone).to_date
        scheduled(preference, entity, user, now, today)
        Agent::Digest::Events.check(user: user, entity: entity, today: today).each { |digest| Agent::Digest::Deliver.call(digest) }
      end
    end
  end

  private

  def scheduled(preference, entity, user, now, today)
    return unless preference.due?(now)

    digest = Agent::Digest::Build.call(user: user, entity: entity, today: today, sections: preference.sections)
    ActsAsTenant.with_tenant(entity) { preference.update!(last_built_at: now) }
    Agent::Digest::Deliver.call(digest) if digest
  end
end

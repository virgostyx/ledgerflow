# Whether the agent may answer this person for this entity, at this moment (A01). Checked at every question, so that switching the agent off, or taking the
# right away, takes effect on the next message. The emergency switch is a platform setting read each time: AGENT_KILL_SWITCH (decision D9).
module Agent::Access
  def self.check(context)
    return :disabled_platform if ENV["AGENT_KILL_SWITCH"].present?
    return :feature_off unless context.entity.feature?(:agent)
    return :not_enabled unless ActsAsTenant.with_tenant(context.entity) { Agent::Setting.find_by(entity: context.entity)&.enabled? }
    return :forbidden unless context.allows?("agent.use")

    nil
  end

  def self.check!(context)
    reason = check(context)
    raise Agent::Unavailable, reason if reason
  end
end

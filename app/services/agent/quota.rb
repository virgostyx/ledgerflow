# How much a person may ask, and how many answers an entity may have being written at once (A01, decision D7). Counted from the questions already stored, in the database,
# not in the memory of a process (decision D10): the count is the same on every server and survives a restart.
module Agent::Quota
  STALE_AFTER = 5.minutes

  # nil when the question may go ahead, otherwise why not: :per_hour, :per_day or :busy.
  def self.check(user:, entity:, limits: Agent::Config.quotas)
    questions = Agent::Message.user.joins(:conversation).where(agent_conversations: { user_id: user.id, entity_id: entity.id })
    return :per_hour if questions.where(agent_messages: { created_at: 1.hour.ago.. }).count >= limits[:per_hour]
    return :per_day  if questions.where(agent_messages: { created_at: 1.day.ago.. }).count >= limits[:per_day]
    return :busy     if ActsAsTenant.with_tenant(entity) { Agent::Conversation.where(answering_since: STALE_AFTER.ago..).count } >= limits[:concurrent_per_entity]

    nil
  end

  def self.message(reason, limits = Agent::Config.quotas)
    case reason
    when :per_hour then "You reached the limit of #{limits[:per_hour]} questions per hour. Try again a little later."
    when :per_day  then "You reached the limit of #{limits[:per_day]} questions per day. Try again tomorrow."
    else "The assistant is busy answering other questions for this entity. Try again in a moment."
    end
  end
end

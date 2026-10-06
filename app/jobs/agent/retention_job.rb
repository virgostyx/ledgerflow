# Deletes what was said to the agent once the entity's retention has passed (A04): the conversations that were not touched for that long, with their messages, tool calls, opinions and
# pseudonyms, and the excerpts of the security events. The audit trail stays: it says what was consulted and when, never what was said. Run every day, on the batch queue.
class Agent::RetentionJob < ApplicationJob
  queue_as :agent_batch

  def perform
    ActsAsTenant.without_tenant do
      Entity.find_each do |entity|
        ActsAsTenant.with_tenant(entity) do
          days = Agent::Setting.find_by(entity: entity)&.retention_days || Agent::Setting.column_defaults.fetch("retention_days")
          limit = days.days.ago
          Agent::Conversation.where(updated_at: ...limit).find_each(&:destroy!)
          Agent::SecurityEvent.where(conversation_id: nil, created_at: ...limit).where.not(excerpt: nil).find_each { |event| event.update_columns(excerpt: nil) }
        end
      end
    end
  end
end

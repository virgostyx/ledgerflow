# What the specs of the agent need to switch it on for an entity: the feature, the owner's setting and the acceptance of the data processing terms (A04).
module AgentHelpers
  def enable_agent!(entity_record = ActsAsTenant.current_tenant)
    ActsAsTenant.with_tenant(entity_record) do
      entity_record.update!(features: entity_record.features.merge("agent" => true))
      Agent::Setting.for_current_entity.update!(enabled: true)
      accept_agent_consent!(entity_record)
    end
  end

  def accept_agent_consent!(entity_record = ActsAsTenant.current_tenant)
    ActsAsTenant.with_tenant(entity_record) { Agent::Consent.accept!(create(:user)) }
  end
end

RSpec.configure { |config| config.include AgentHelpers }

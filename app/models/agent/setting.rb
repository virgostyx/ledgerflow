# The agent's settings for one entity (A01): off until an owner turns it on. The other settings of the spec (data modes, budget, document mode)
# arrive with their capability.
class Agent::Setting < ApplicationRecord
  self.table_name = "agent_settings"

  RETENTION_CHOICES = [ 30, 90, 365 ].freeze

  acts_as_tenant :entity

  validates :retention_days, inclusion: { in: RETENTION_CHOICES }

  def self.for_current_entity = find_or_create_by!(entity: ActsAsTenant.current_tenant)
end

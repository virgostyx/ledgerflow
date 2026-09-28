# Nightly consistency check (R19): one run per entity, each in its own tenant.
class Accounting::ConsistencyCheckJob < ApplicationJob
  queue_as :default

  def perform(entity_id = nil)
    entities = entity_id ? Entity.where(id: entity_id) : Entity.all
    entities.find_each do |entity|
      ActsAsTenant.with_tenant(entity) { Accounting::Consistency::Runner.call(trigger: entity_id ? "manual" : "nightly") }
    end
  end
end

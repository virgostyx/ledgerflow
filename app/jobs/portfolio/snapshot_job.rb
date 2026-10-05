# F12a: writes the health snapshot of one entity, in its own tenant.
class Portfolio::SnapshotJob < ApplicationJob
  queue_as :default

  def perform(entity_id)
    entity = Entity.find_by(id: entity_id) or return
    ActsAsTenant.with_tenant(entity) { Portfolio::Snapshot.call(entity) } if entity.feature?(:f12)
  end
end

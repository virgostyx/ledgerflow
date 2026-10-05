# F12a: runs the consistency checks (R19) of one entity from the portfolio, then refreshes its snapshot. Writes no accounting entry.
class Portfolio::RunChecksJob < ApplicationJob
  queue_as :default

  def perform(entity_id)
    entity = Entity.find_by(id: entity_id) or return
    ActsAsTenant.with_tenant(entity) do
      Accounting::Consistency::Runner.call(trigger: "portfolio")
      Portfolio::Snapshot.call(entity)
    end
  end
end

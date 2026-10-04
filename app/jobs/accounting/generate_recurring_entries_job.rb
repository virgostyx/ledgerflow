# Daily (F07): makes the recurring entries that have come due, entity by entity. => number of entries made
class Accounting::GenerateRecurringEntriesJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each.sum { |entity| ActsAsTenant.with_tenant(entity) { Accounting::GenerateRecurringEntries.call } }
  end
end

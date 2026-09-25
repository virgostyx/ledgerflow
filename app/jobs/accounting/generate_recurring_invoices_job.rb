# Daily: generates the drafts that the recurring invoices of every active entity owe (Accounting::RunRecurringInvoices).
# A job runs with no tenant, so each entity is processed inside its own; one entity failing does not stop the others.
class Accounting::GenerateRecurringInvoicesJob < ApplicationJob
  queue_as :default

  def perform(on = Date.current)
    Entity.active.find_each do |entity|
      ActsAsTenant.with_tenant(entity) { Accounting::RunRecurringInvoices.call(on: on) }
    rescue StandardError => e
      Rails.logger.error("[recurring invoices] entity #{entity.id}: #{e.class}: #{e.message}")
    end
  end
end

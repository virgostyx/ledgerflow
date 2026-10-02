# Weekly: every stored document is checked against its checksum (F03), each entity in its own tenant. A document the
# storage could not be read for is counted as an error and tried again next time; it is never called missing.
class Accounting::VerifyDocumentsJob < ApplicationJob
  queue_as :default

  # => { checked:, failed:, errors: }
  def perform(entity_id = nil)
    totals = { checked: 0, failed: 0, errors: 0 }
    self.class.sweep(entity_id).each_value do |result|
      totals[:checked] += result[:checked]
      totals[:failed] += result[:failures].size
      totals[:errors] += result[:errors]
    end
    totals
  end

  # => { entity => { checked:, failures: [[document, status]], errors: } }
  def self.sweep(entity_id = nil)
    entities = entity_id ? Entity.where(id: entity_id) : Entity.all
    entities.find_each.to_h do |entity|
      result = { checked: 0, failures: [], errors: 0 }
      ActsAsTenant.with_tenant(entity) do
        Accounting::Document.find_each do |document|
          result[:checked] += 1
          outcome = Accounting::VerifyDocument.call(document: document)
          result[:failures] << [ document, outcome[:status] ] unless outcome[:status] == "ok"
        rescue StandardError => e
          result[:errors] += 1
          Rails.logger.error("[documents:verify] document ##{document.id}: #{e.class}: #{e.message}")
        end
      end
      [ entity, result ]
    end
  end
end

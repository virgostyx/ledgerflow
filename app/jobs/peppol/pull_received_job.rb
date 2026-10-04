# F06 step 6: a net under the webhooks. For each entity whose Access Point makes us fetch what it received (B2Brouter), lists the received documents
# of the last days and records those we do not know, as a webhook would have: a webhook that was lost (the endpoint was down, a 404) costs a
# few minutes, not a document. Idempotent: a document is one message, by its Access Point identifier. => number of documents recorded
class Peppol::PullReceivedJob < ApplicationJob
  queue_as :default

  LOOKBACK = 30.days

  def perform
    Entity.where.not(peppol_access_point: nil).find_each.sum do |entity|
      ActsAsTenant.with_tenant(entity) { pull(entity) }
    rescue Peppol::AccessPoint::Error => e
      Rails.logger.warn("[Peppol] #{entity.name}: received documents could not be listed: #{e.message}")
      0
    end
  end

  private

  def pull(entity)
    access_point = Peppol::AccessPoint.for(entity)
    return 0 unless access_point.fetches_received?

    listed = access_point.list_received(since: LOOKBACK.ago)
    known = Accounting::PeppolMessage.inbound.where(message_id: listed.pluck(:message_id)).pluck(:message_id)
    (listed.reject { |doc| known.include?(doc[:message_id]) }).count do |doc|
      Peppol::ReceiveMessage.call(event: Peppol::Event.new(kind: :received, message_id: doc[:message_id], remote_id: doc[:remote_id], receiver: entity.peppol_participant_id))
      true
    end
  end
end

# Reads a batch of documents with the model (A09), one after the other, each on its own: one that fails does not stop the others. Started by a person who chose the documents and saw the estimate; never by
# the arrival of a document. The results wait in the "To confirm" queue.
class Agent::DocumentBatchJob < ApplicationJob
  queue_as :agent_batch

  def perform(user_id, entity_id, document_ids, batch_key)
    entity = ActsAsTenant.without_tenant { Entity.find(entity_id) }
    user = User.find(user_id)
    ActsAsTenant.with_tenant(entity) do
      Accounting::Document.where(id: document_ids).find_each do |document|
        Agent::Documents::Extract.call(document: document, user: user, batch_key: batch_key)
      rescue StandardError => e
        Rails.logger.error("[agent] document #{document.id} failed in batch #{batch_key}: #{e.class}")
        Agent::DocumentExtraction.create!(document: document, requested_by: user, engine: "agent_text", status: "failed", error: "The reading failed (#{e.class.name.demodulize})", batch_key: batch_key)
      end
    end
  end
end

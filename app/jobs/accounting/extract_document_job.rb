# Reads a document in the background (F03). Three attempts with growing delays; the document keeps a visible status
# ("pending", then "done" or "failed" with the error). Runs in the tenant of the document's entity.
class Accounting::ExtractDocumentJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound # the document was deleted meanwhile

  def perform(document_id, entity_id)
    ActsAsTenant.with_tenant(Entity.find(entity_id)) do
      Accounting::ExtractDocument.call(document: Accounting::Document.find(document_id))
    end
  end
end

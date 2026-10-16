# B02b: the firm refuses a document that came from the portal, with one of the reasons the client may be told. The document itself is not deleted (the books keep what they received);
# the client is told, once. Only a document of the inbox, from the portal, and not yet booked.
class PortalAdmin::RejectUpload
  REASONS = %w[illegible duplicate out_of_scope].freeze

  def self.call(document:, reason:, by:)
    context = LightService::Context.make(document: document)
    return context.tap { |c| c.fail!("Choose one of the listed reasons.") } unless REASONS.include?(reason.to_s)
    return context.tap { |c| c.fail!("This document did not come from the portal.") } unless document.portal?
    return context.tap { |c| c.fail!("A document that is linked cannot be refused.") } unless document.inbox?

    uploads = Portal::Upload.where(document_id: document.id, entity_id: document.entity_id, status: %w[accepted to_complete]).to_a
    return context.tap { |c| c.fail!("This document is not waiting for an answer.") } if uploads.empty?

    ApplicationRecord.transaction do
      ActsAsTenant.with_tenant(document.entity) { Accounting::AuditLog.record!(auditable: document, action: "portal_upload_rejected", user: by, payload: { reason: reason, uploads: uploads.map(&:token) }) }
      uploads.each { |upload| upload.update!(status: "refused", refusal_reason: reason) }
    end
    PortalAdmin::NotifyUpload.call(uploads.first)
    context
  end
end

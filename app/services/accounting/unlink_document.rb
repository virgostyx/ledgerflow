# Detaches a document. What justifies a validated entry stays attached (the document can then only be archived).
class Accounting::UnlinkDocument
  def self.call(link:, user:)
    ctx = LightService::Context.make(link: link)
    target = link.target
    document = link.document
    return ctx.tap { |c| c.fail!(I18n.t("documents.errors.evidence")) } if target.is_a?(Accounting::JournalEntry) && !target.draft?

    ApplicationRecord.transaction do
      link.destroy!
      document.update!(status: :inbox) if document.linked? && document.links.reload.empty?
      Accounting::AuditLog.record!(auditable: document, action: "document_unlink", user: user,
                                   payload: { target_type: link.target_type, target_id: link.target_id })
    end
    ctx
  end
end

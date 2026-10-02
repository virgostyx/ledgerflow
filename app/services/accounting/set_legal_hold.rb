# Places a document under legal hold, or releases it (F03). While it lasts nothing is deleted, whatever the retention
# term. A reason is needed to place it, and both are audited with their reason. It is a retention control: it works on a
# document frozen by a validated entry, whose file and details stay as they are.
class Accounting::SetLegalHold
  def self.call(document:, hold:, reason:, user:)
    ctx = LightService::Context.make(document: document)
    reason = reason.to_s.strip
    return ctx if document.legal_hold == hold
    return ctx.tap { |c| c.fail!(I18n.t("documents.errors.legal_hold_reason")) } if hold && reason.blank?

    ApplicationRecord.transaction do
      document.update!(legal_hold: hold, legal_hold_reason: hold ? reason : nil)
      Accounting::AuditLog.record!(auditable: document, action: "document_legal_hold", user: user, reason: reason.presence, payload: { hold: hold })
    end
    ctx
  end
end

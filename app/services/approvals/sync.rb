# Keeps an approval honest (B01a §4.5): when the content of a purchase invoice no longer matches the one that was put to
# approval, the approval (given or waiting) is invalidated and the circuit starts again from the first level, with the reason.
# Called after a save of the invoice, of one of its lines, or of one of its documents. Free labels do not change the fingerprint.
class Approvals::Sync
  def self.call(invoice)
    return unless invoice.supplier? && invoice.entity.feature?(:b01a)

    current = Approvals::Request.where(subject: invoice, status: %i[pending approved]).order(:id).last
    return unless current

    fingerprint = Approvals::ContentFingerprint.call(invoice)
    return if fingerprint == current.content_fingerprint

    ApplicationRecord.transaction do
      current.update!(status: :invalidated, decided_at: Time.current, invalidation_reason: I18n.t("approvals.invalidated.content_changed"))
      Accounting::AuditLog.record!(auditable: invoice, action: "approval_invalidated",
                                   payload: { request_id: current.id, was: current.content_fingerprint, now: fingerprint })
      Approvals::Submit.call(invoice: invoice, user: current.submitted_by)
    end
  end
end

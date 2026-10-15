# B03c: revokes a certificate that was issued by mistake, with a reason. Not because later entries changed the periods it covers: it attests the state at its instant. Once.
module Integrity::RevokeCertificate
  def self.call(certificate:, user:, reason:)
    ctx = LightService::Context.make(certificate: certificate)
    return ctx.tap { |c| c.fail!(I18n.t("integrity.errors.reason_needed")) } if reason.blank?
    return ctx.tap { |c| c.fail!(I18n.t("integrity.errors.already_revoked")) } if certificate.revoked?

    ApplicationRecord.transaction do
      certificate.update!(revoked_at: Time.current, revoked_by: user, revocation_reason: reason)
      Accounting::AuditLog.record!(auditable: certificate, action: "integrity_certificate_revoked", user: user, reason: reason, payload: { uuid: certificate.uuid })
    end
    ctx
  end
end

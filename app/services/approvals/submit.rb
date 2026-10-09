# Puts a purchase invoice to approval (B01a): the first matching policy decides who must approve; with none, the invoice
# needs no approval and that is recorded. Submitting twice on the same content changes nothing.
# => ctx[:request] (nil when no approval is needed)
class Approvals::Submit
  OPEN_STATUSES = %w[draft posted partially_paid].freeze

  def self.call(invoice:, user: nil)
    ctx = LightService::Context.make(request: nil)
    return ctx.tap { |c| c.fail!(I18n.t("approvals.errors.feature_off")) } unless invoice.entity.feature?(:b01a)
    return ctx.tap { |c| c.fail!(I18n.t("approvals.errors.not_a_purchase_invoice")) } unless invoice.supplier?
    return ctx.tap { |c| c.fail!(I18n.t("approvals.errors.not_open")) } unless OPEN_STATUSES.include?(invoice.status)

    ApplicationRecord.transaction do
      # One submission at a time per invoice, so that two clicks cannot open two requests.
      invoice.lock!
      fingerprint = Approvals::ContentFingerprint.call(invoice)
      existing = Approvals::Request.where(subject: invoice, content_fingerprint: fingerprint, status: %i[pending approved]).order(:id).last
      next ctx[:request] = existing if existing

      policy = Approvals::PolicyMatcher.call(invoice)
      if policy
        ctx[:request] = open_request(invoice, policy, fingerprint, user)
        invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:to_approve])
        Accounting::AuditLog.record!(auditable: invoice, action: "approval_submitted", user: user,
                                     payload: { request_id: ctx[:request].id, policy_id: policy.id, policy_version: policy.version, content_fingerprint: fingerprint })
      else
        invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:not_required])
        Accounting::AuditLog.record!(auditable: invoice, action: "approval_not_required", user: user, payload: { content_fingerprint: fingerprint })
      end
    end
    ctx
  end

  def self.open_request(invoice, policy, fingerprint, user)
    Approvals::Request.create!(subject: invoice, policy: policy, policy_version: policy.version, content_fingerprint: fingerprint,
                               submitted_by: user, submitted_at: Time.current, step_started_at: Time.current)
  end
  private_class_method :open_request
end

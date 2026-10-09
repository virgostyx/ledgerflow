# B01a: an entity may ask for the "bon à payer" before a purchase invoice is validated (bap_before_posting). Without
# that option the approval only conditions the payment, never the accounting.
class Accounting::Actions::ValidateApprovalBeforePosting
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    invoice = ctx.invoice
    next unless invoice.supplier? && invoice.entity.feature?(:b01a) && invoice.entity.bap_before_posting?
    next unless Approvals::PolicyMatcher.call(invoice)

    approved = Approvals::Request.approved.exists?(subject: invoice, content_fingerprint: Approvals::ContentFingerprint.call(invoice))
    ctx.fail_with_rollback!(I18n.t("approvals.errors.approval_before_posting")) unless approved
  end
end

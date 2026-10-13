# Puts a payment batch to approval (B01b, the engine of B01a with the subject payment_batch): the batch must be a draft whose pre-flight is ready (no error, every
# warning acknowledged), and a policy must cover it: nobody authorizes a payment by default. Submitting twice on the same content changes nothing.
# => ctx[:request]
class Payments::SubmitBatch
  def self.call(batch:, user:)
    ctx = LightService::Context.make(request: nil)
    return fail(ctx, :batch_feature_off) unless batch.entity.feature?(:b01b)
    return fail(ctx, :batch_not_allowed) unless Payments::BatchPolicy.new(user, batch).prepare?
    return fail(ctx, :batch_not_draft) unless batch.draft?
    return fail(ctx, :batch_no_profile) unless Payments::Sepa::Pain001Builder::VERSIONS.include?(batch.bank_profile&.format_version) # the format comes from the bank, not from a guess

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id) # one submission at a time per batch
      fingerprint = Approvals::ContentFingerprint.call(batch)
      existing = Approvals::Request.where(subject: batch, content_fingerprint: fingerprint, status: :pending).order(:id).last
      next ctx[:request] = existing if existing
      next fail(ctx, :batch_not_ready) unless Payments::Preflight.call(batch).ready?

      policy = Approvals::PolicyMatcher.call(batch)
      next fail(ctx, :batch_no_policy) unless policy

      request = Approvals::Request.create!(subject: batch, policy: policy, policy_version: policy.version, content_fingerprint: fingerprint,
                                           submitted_by: user, submitted_at: Time.current, step_started_at: Time.current)
      batch.update!(status: :pending_approval, approval_request: request)
      Accounting::AuditLog.record!(auditable: batch, action: "approval_submitted", user: user,
                                   payload: { request_id: request.id, policy_id: policy.id, policy_version: policy.version, content_fingerprint: fingerprint })
      ctx[:request] = request
    end
    ctx
  end

  def self.fail(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("approvals.errors.#{code}"))
    ctx
  end
  private_class_method :fail
end

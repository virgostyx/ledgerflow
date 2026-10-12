# Completes the cancellation of an exported batch (B01b): the person says the file is not, or is no longer, authorized in their bank. The invoices are free again.
class Payments::ConfirmCancellation
  def self.call(batch:, user:)
    ctx = LightService::Context.make
    return refuse(ctx, :feature_off) unless batch.entity.feature?(:b01b)
    return refuse(ctx, :not_allowed) unless Payments::BatchPolicy.new(user, batch).confirm?

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id)
      next refuse(ctx, :not_asked) unless batch.reload.cancel_requested?

      batch.update!(status: :cancelled, cancelled_at: Time.current)
      Accounting::AuditLog.record!(auditable: batch, action: "payment_batch_cancelled", user: user, reason: batch.cancel_reason, payload: { reason: batch.cancel_reason, from: "cancel_requested" })
    end
    ctx
  end

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.cancel.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end

# Gives up a payment batch, with a reason (B01b §5 "Après l'export"). Before the file was made the batch is cancelled and its invoices are free at once.
# Once the file exists it may already be in the bank: the batch only becomes `cancel_requested`, its invoices stay held, and a person completes the cancellation
# (Payments::ConfirmCancellation) when the file is not, or no longer, authorized there. A batch that was debited cannot be cancelled.
class Payments::CancelBatch
  BEFORE_FILE = %w[draft pending_approval approved].freeze
  AFTER_FILE = %w[exported submitted].freeze

  def self.call(batch:, user:, reason:)
    ctx = LightService::Context.make
    code = refusal_for(batch, user, reason)
    return refuse(ctx, code) if code

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id)
      was = batch.reload.status
      next refuse(ctx, :cannot_cancel) unless (BEFORE_FILE + AFTER_FILE).include?(was)

      BEFORE_FILE.include?(was) ? give_up(batch, user, reason, was) : ask_for(batch, user, reason, was)
    end
    ctx
  end

  def self.refusal_for(batch, user, reason)
    return :feature_off unless batch.entity.feature?(:b01b)
    return :reason_required if reason.to_s.strip.empty?

    policy = Payments::BatchPolicy.new(user, batch)
    :not_allowed unless BEFORE_FILE.include?(batch.status) ? policy.prepare? : policy.confirm?
  end
  private_class_method :refusal_for

  def self.give_up(batch, user, reason, was)
    batch.approval_request&.update!(status: :cancelled, decided_at: Time.current) if batch.approval_request&.pending?
    batch.update!(status: :cancelled, cancel_reason: reason.to_s.strip, cancelled_by: user, cancelled_at: Time.current)
    Accounting::AuditLog.record!(auditable: batch, action: "payment_batch_cancelled", user: user, reason: reason, payload: { reason: reason.to_s.strip, from: was })
  end
  private_class_method :give_up

  def self.ask_for(batch, user, reason, was)
    batch.update!(status: :cancel_requested, cancel_reason: reason.to_s.strip, cancelled_by: user)
    Accounting::AuditLog.record!(auditable: batch, action: "payment_batch_cancel_requested", user: user, reason: reason, payload: { reason: reason.to_s.strip, from: was })
  end
  private_class_method :ask_for

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.cancel.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end

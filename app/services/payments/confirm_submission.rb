# "I loaded the file in my bank" (B01b §5): the person says, with the right to confirm, that the file of an exported batch went to their bank. LedgerFlow cannot
# see it and initiates nothing: this is a statement, timed and recorded. The invoices stay held; what the bank did is told by the statement (B01c).
class Payments::ConfirmSubmission
  def self.call(batch:, user:)
    ctx = LightService::Context.make
    return refuse(ctx, :feature_off) unless batch.entity.feature?(:b01b)
    return refuse(ctx, :not_allowed) unless Payments::BatchPolicy.new(user, batch).confirm?

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id)
      next refuse(ctx, :not_exported) unless batch.reload.exported?

      batch.update!(status: :submitted, submitted_by: user, submitted_at: Time.current)
      Accounting::AuditLog.record!(auditable: batch, action: "payment_batch_submitted", user: user,
                                   payload: { sha256: batch.file_sha256, payments: batch.payments_count, total: format("%.2f", batch.total), message_id: batch.message_id })
    end
    ctx
  end

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.confirm.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end

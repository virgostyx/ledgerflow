# A payment missing from the debit of a batch the bank debited in part is rejected (B01c §6 "Rejet avant débit"): by a person with the right to confirm, with a reason. The invoice
# comes back approved but held (nothing pays it again by itself to the same account), the account goes back to unverified, the supplier is to be contacted. Once no payment of the
# batch waits any more, the batch is closed: partly rejected. => ctx[:items]; on a refusal ctx[:code]
class Payments::RejectPayments
  WAITING = Payments::ConfirmDebit::WAITING

  def self.call(batch:, items:, user:, reason:)
    ctx = LightService::Context.make(items: [])
    items = Array(items)
    code = refusal_for(batch, user, items, reason)
    return refuse(ctx, code) if code

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id)
      next refuse(ctx, :not_waiting) unless WAITING.include?(batch.reload.status)
      next refuse(ctx, :foreign_items) unless (items.map(&:id) - batch.items.where(status: :included).pluck(:id)).empty?

      items.each do |item|
        item.update!(status: :rejected, exclusion_reason: reason.to_s.strip)
        Payments::HoldAfterFailedPayment.call(item: item, outcome: "rejected", reason: reason.to_s.strip, user: user)
        Accounting::AuditLog.record!(auditable: batch, action: "payment_rejected", user: user, payload: { item_id: item.id, end_to_end_id: item.end_to_end_id, reason: reason.to_s.strip })
      end
      ctx[:items] = items
      batch.update!(status: :partially_rejected, debited_at: Time.current, debited_by: user, debit_kind: batch.debit_kind || "statement") if batch.items.reload.none?(&:included?)
    end
    ctx
  end

  def self.refusal_for(batch, user, items, reason)
    return :feature_off unless batch.entity.feature?(:b01b)
    return :not_allowed unless Payments::BatchPolicy.new(user, batch).confirm?
    return :reason_required if reason.to_s.strip.empty?
    return :not_waiting unless WAITING.include?(batch.status)

    :foreign_items unless items.any? && (items.map(&:id) - batch.items.where(status: :included).pluck(:id)).empty?
  end
  private_class_method :refusal_for

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.debit.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end

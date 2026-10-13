# The statement line of a debit that was confirmed by hand (B01c §6 "Confirmation manuelle"): once recognised, it is tied to the payments it paid. No entry is made (they exist); the
# line is settled when those entries are validated. The batch then stops being flagged by R19. => ctx[:code] on a refusal
class Payments::LinkManualDebit
  def self.call(batch:, user:, transaction:, items:)
    ctx = LightService::Context.make
    items = Array(items)
    code = refusal_for(batch, user, transaction, items)
    return refuse(ctx, code) if code

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id)
      next refuse(ctx, :line_not_pending) unless transaction.reload.pending?
      next refuse(ctx, :foreign_items) unless (items.map(&:id) - open_ids(batch)).empty?

      items.each { |item| item.update!(bank_transaction: transaction) }
      transaction.update!(status: items.all? { |item| item.journal_entry&.posted? } ? :reconciled : :matched,
                          match_data: { "kind" => "payment_batch", "batch_id" => batch.id, "item_ids" => items.map(&:id), "entry_ids" => items.map(&:journal_entry_id), "linked" => true })
      Accounting::AuditLog.record!(auditable: batch, action: "payment_batch_debit_linked", user: user, payload: { transaction_id: transaction.id, items: items.size, total: format("%.2f", items.sum(&:amount)) })
    end
    ctx
  end

  def self.open_ids(batch) = batch.items.where(status: :confirmed, bank_transaction_id: nil).pluck(:id)
  private_class_method :open_ids

  def self.refusal_for(batch, user, transaction, items)
    return :feature_off unless batch.entity.feature?(:b01b)
    return :not_allowed unless Payments::BatchPolicy.new(user, batch).confirm?
    return :not_waiting unless batch.debited? && batch.debit_kind == "manual"
    return :not_a_debit unless transaction.debit?
    return :line_not_pending unless transaction.pending?
    return :wrong_account if transaction.bank_account_id != batch.bank_account_id
    return :foreign_items unless items.any? && (items.map(&:id) - open_ids(batch)).empty?

    :amount_mismatch if items.sum(&:amount) != -transaction.amount
  end
  private_class_method :refusal_for

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.debit.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end

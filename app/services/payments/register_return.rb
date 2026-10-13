# Registers that a payment came back (B01c §6 "Retour après débit"), by a person with the rights to confirm payments and to reverse entries: the entry of the payment is reversed (F07,
# unlettering it, the same date as the credit line), the line of the statement is settled against the reversal, the invoice is open again and held, the account goes back to unverified
# and the supplier is to be contacted. The payment is `returned`. => ctx[:reversal]; on a refusal ctx[:code]
class Payments::RegisterReturn
  def self.call(item:, transaction:, user:, reason:)
    ctx = LightService::Context.make(reversal: nil)
    batch = item.batch
    code = refusal_for(item, batch, transaction, user, reason)
    return refuse(ctx, code) if code

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id)
      next refuse(ctx, :already_returned) unless item.reload.confirmed? && transaction.reload.pending?

      reversal = Accounting::ReverseJournalEntry.call(entry: item.journal_entry, from_source: true, reason: reason.to_s.strip, user: user, confirm_unletter: true, date: transaction.transaction_date)
      next refuse(ctx, :reversal_failed, I18n.t("payments.debit.errors.reversal_failed", message: reversal.message)) && raise(ActiveRecord::Rollback) if reversal.failure?

      transaction.update!(status: :reconciled, journal_entry: reversal[:reversal], match_data: { "kind" => "payment_returned", "item_id" => item.id })
      item.update!(status: :returned)
      Payments::HoldAfterFailedPayment.call(item: item, outcome: "returned", reason: reason.to_s.strip, user: user)
      Accounting::AuditLog.record!(auditable: batch, action: "payment_returned", user: user,
                                   payload: { item_id: item.id, end_to_end_id: item.end_to_end_id, transaction_id: transaction.id, reversal_id: reversal[:reversal].id, reason: reason.to_s.strip })
      ctx[:reversal] = reversal[:reversal]
    end
    ctx
  end

  def self.refusal_for(item, batch, transaction, user, reason)
    return :feature_off unless batch.entity.feature?(:b01b)
    return :not_allowed unless Payments::BatchPolicy.new(user, batch).reverse_payments?
    return :reason_required if reason.to_s.strip.empty?
    return :not_confirmed unless item.confirmed? && item.journal_entry&.posted?
    return :not_a_credit unless transaction.credit?
    return :line_not_pending unless transaction.pending?
    return :wrong_account if transaction.bank_account_id != batch.bank_account_id

    :amount_mismatch if transaction.amount != item.amount
  end
  private_class_method :refusal_for

  def self.refuse(ctx, code, message = nil)
    ctx[:code] = code
    ctx.fail!(message || I18n.t("payments.debit.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end

# Links a bank debit to the settlement entry of a payment batch, instead of booking the same payment a second
# time via ReconcileBankTransaction. If the batch was not confirmed yet (still generated), the debit proves the
# file was executed: the batch is executed first (settlement entry, invoices paid). All or nothing.
class Accounting::LinkTransactionToSettlement
  extend LightService::Organizer

  def self.call(transaction:, payment_batch:)
    error = guard(transaction, payment_batch)
    return failure(transaction, error) if error

    result = nil
    ApplicationRecord.transaction do
      result = Payments::ExecutePaymentBatch.call(payment_batch: payment_batch) if payment_batch.generated?
      if result.nil? || result.success?
        result = with(transaction: transaction, journal_entry: payment_batch.reload.journal_entry)
                   .reduce(Accounting::Actions::MarkTransactionReconciled)
      end
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  end

  def self.guard(tx, batch)
    if tx.reconciled?                                             then "Transaction already reconciled"
    elsif !(batch.generated? || batch.executed?)                  then "Payment batch is not generated or executed"
    elsif tx.amount != -batch.total_amount                        then "Amount does not match the batch"
    elsif batch.journal_entry && Accounting::BankTransaction.exists?(journal_entry: batch.journal_entry)
      "Batch already linked to a transaction"
    end
  end

  def self.failure(tx, message)
    LightService::Context.make(transaction: tx).tap { |ctx| ctx.fail!(message) }
  end
  private_class_method :guard, :failure
end

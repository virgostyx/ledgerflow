# Links a bank debit to the settlement entry Payments::ExecutePaymentBatch already posted,
# instead of booking the same payment a second time via ReconcileBankTransaction.
class Accounting::LinkTransactionToSettlement
  extend LightService::Organizer

  def self.call(transaction:, payment_batch:)
    error = guard(transaction, payment_batch)
    return failure(transaction, error) if error

    with(transaction: transaction, journal_entry: payment_batch.journal_entry)
      .reduce(Accounting::Actions::MarkTransactionReconciled)
  end

  def self.guard(tx, batch)
    if tx.reconciled?                                                   then "Transaction already reconciled"
    elsif !batch.executed? || batch.journal_entry.nil?                  then "Payment batch is not executed"
    elsif tx.amount != -batch.total_amount                              then "Amount does not match the batch"
    elsif Accounting::BankTransaction.exists?(journal_entry: batch.journal_entry) then "Batch already linked to a transaction"
    end
  end

  def self.failure(tx, message)
    LightService::Context.make(transaction: tx).tap { |ctx| ctx.fail!(message) }
  end
  private_class_method :guard, :failure
end

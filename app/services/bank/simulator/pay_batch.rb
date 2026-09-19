# Simulates the bank booking a generated pain.001 batch: one grouped debit for the total,
# referenced by the batch message id (what a matcher can look up via PaymentBatch#message_id).
# ponytail: real CAMT carries this in NtryDtls/Btch/PmtInfId; we reuse EndToEndId so the
# existing parser needs no change. Extend the parser when importing real bank files.
class Bank::Simulator::PayBatch
  def self.call(payment_batch:)
    raise ArgumentError, "batch has no message_id (not generated)" if payment_batch.message_id.blank?

    Bank::Simulator::BuildStatement.call(
      iban: payment_batch.bank_account.iban,
      entries: [ {
        date:        payment_batch.requested_execution_date,
        amount:      -payment_batch.total_amount,
        reference:   payment_batch.message_id,
        description: "SEPA batch #{payment_batch.message_id}"
      } ]
    )
  end
end

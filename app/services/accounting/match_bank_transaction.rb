# Suggests what a bank transaction corresponds to. Never writes anything.
# ponytail: no IBAN+amount rule yet (the CAMT parser drops counterparty IBAN); add when the parser keeps it.
class Accounting::MatchBankTransaction
  Suggestion = Struct.new(:kind, :target, :confidence, keyword_init: true)

  def self.call(transaction:)
    match_batch(transaction) || match_invoice(transaction)
  end

  def self.match_batch(tx)
    return unless tx.debit? && tx.reference.present?

    batch = Accounting::PaymentBatch.executed.find_by(message_id: tx.reference)
    Suggestion.new(kind: :payment_batch, target: batch, confidence: :high) if batch && batch.total_amount == -tx.amount
  end

  def self.match_invoice(tx)
    return unless tx.credit? && (digits = Accounting::StructuredCommunication.extract(tx.description))

    invoice = Accounting::Invoice.customer.posted.find_by(id: Accounting::StructuredCommunication.id_from(digits))
    return unless invoice && tx.amount <= invoice.remaining_amount

    Suggestion.new(kind: :invoice, target: invoice, confidence: tx.amount == invoice.remaining_amount ? :high : :medium)
  end
  private_class_method :match_batch, :match_invoice
end

# Suggests what a bank transaction corresponds to. Never writes anything.
# ponytail: no IBAN+amount rule yet (the CAMT parser drops counterparty IBAN); add when the parser keeps it.
class Accounting::MatchBankTransaction
  Suggestion = Struct.new(:kind, :target, :confidence, :excess, keyword_init: true)

  def self.call(transaction:)
    match_batch(transaction) || match_invoice(transaction) || match_invoices(transaction)
  end

  def self.match_batch(tx)
    return unless tx.debit? && tx.reference.present?

    batch = Accounting::PaymentBatch.executed.find_by(message_id: tx.reference)
    Suggestion.new(kind: :payment_batch, target: batch, confidence: :high) if batch && batch.total_amount == -tx.amount
  end

  def self.match_invoice(tx)
    return unless tx.credit? && (digits = Accounting::StructuredCommunication.extract(tx.description))

    invoice = Accounting::Invoice.customer.posted.find_by(id: Accounting::StructuredCommunication.id_from(digits))
    return unless invoice

    excess = [ tx.amount - invoice.remaining_amount, 0 ].max
    Suggestion.new(kind: :invoice, target: invoice, excess: excess,
                   confidence: tx.amount == invoice.remaining_amount ? :high : :medium)
  end

  # Grouped transfer: several open invoices of one partner named in the description, whose balances add up to the amount.
  # ponytail: scans open customer invoices in Ruby; index/limit by partner if the open-invoice count gets large.
  def self.match_invoices(tx)
    return unless tx.credit? && tx.description.present?

    named = Accounting::Invoice.customer.posted.where.not(invoice_number: nil).select do |invoice|
      tx.description.match?(/(?<![\w-])#{Regexp.escape(invoice.invoice_number)}(?![\w-])/)
    end
    return unless named.size > 1 && named.map(&:partner_id).uniq.one? && named.sum(&:remaining_amount) == tx.amount

    Suggestion.new(kind: :invoices, target: named, excess: 0, confidence: :medium)
  end
  private_class_method :match_batch, :match_invoice, :match_invoices
end

# A credit line of the statement that gives back a payment (B01c §6 "Retour après débit"): the same amount from the account that was paid, within thirty days of the debit. Only
# proposed, and only when one payment fits; the person opens the reversal (Payments::RegisterReturn). Nothing is written here. => Proposal(item), or nil.
class Payments::RecognizeReturn
  Proposal = Struct.new(:item, keyword_init: true)

  DAYS = 30

  def self.call(transaction)
    return unless transaction.pending? && transaction.credit? && transaction.currency == "EUR" && transaction.counterparty_iban.present?

    iban = transaction.counterparty_iban.delete(" ").upcase
    items = Payments::Item.where(status: :confirmed, amount: transaction.amount).joins(:batch).where(payment_batches: { bank_account_id: transaction.bank_account_id })
                          .includes(:bank_transaction, :batch).select { |item| item.iban.delete(" ").upcase == iban && in_time?(item, transaction.transaction_date) }
    Proposal.new(item: items.first) if items.one?
  end

  def self.in_time?(item, date)
    debited_on = item.bank_transaction&.transaction_date || item.batch.debit_date or return false
    (debited_on..(debited_on + DAYS)).cover?(date)
  end
  private_class_method :in_time?
end

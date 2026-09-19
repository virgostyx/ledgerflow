# Books the suggestion MatchBankTransaction computes for a transaction.
# Returns the service result, or nil when there is no suggestion.
class Accounting::AcceptBankSuggestion
  FEES_LABEL = "Bank fees"

  def self.call(transaction:)
    suggestion = Accounting::MatchBankTransaction.call(transaction: transaction)
    return unless suggestion

    fiscal_year = Accounting::FiscalYear.current

    case suggestion.kind
    when :payment_batch
      Accounting::LinkTransactionToSettlement.call(transaction: transaction, payment_batch: suggestion.target)
    when :expense
      Accounting::ReconcileBankTransaction.call(transaction: transaction, account_id: suggestion.target.id,
                                                fiscal_year: fiscal_year, label: FEES_LABEL)
    when :invoices
      Accounting::BookInvoiceReceipt.call(transaction: transaction, invoices: suggestion.target, fiscal_year: fiscal_year)
    when :invoice
      Accounting::BookInvoiceReceipt.call(transaction: transaction, invoice: suggestion.target, fiscal_year: fiscal_year)
    end
  end
end

# Books the suggestion MatchBankTransaction computes for a transaction.
# Returns the service result, or nil when there is no suggestion.
# `draft: true` (whoever cannot validate, and the automatic matches): the payment entry stays a draft and the line is "matched".
# A supplier payment settles by lettering, which needs a validated entry: it has no draft form here.
class Accounting::AcceptBankSuggestion
  FEES_LABEL = "Bank fees"

  def self.call(transaction:, draft: false)
    suggestion = Accounting::MatchBankTransaction.call(transaction: transaction)
    return unless suggestion

    fiscal_year = Accounting::FiscalYear.current

    case suggestion.kind
    when :payment_batch
      Accounting::LinkTransactionToSettlement.call(transaction: transaction, payment_batch: suggestion.target)
    when :expense
      Accounting::ReconcileBankTransaction.call(transaction: transaction, account_id: suggestion.target.id,
                                                fiscal_year: fiscal_year, label: FEES_LABEL, draft: draft)
    when :rule
      rule = suggestion.target
      Accounting::ReconcileBankTransaction.call(transaction: transaction, account_id: rule.account_id, fiscal_year: fiscal_year,
                                                label: rule.name, partner: rule.partner, draft: draft)
    when :invoices
      Accounting::BookInvoiceReceipt.call(transaction: transaction, invoices: suggestion.target, fiscal_year: fiscal_year, draft: draft)
    when :invoice
      Accounting::BookInvoiceReceipt.call(transaction: transaction, invoice: suggestion.target, fiscal_year: fiscal_year, draft: draft)
    when :supplier_invoice
      return LightService::Context.make(transaction: transaction).tap { |ctx| ctx.fail!(I18n.t("banking.match.supplier_needs_validation")) } if draft

      Accounting::PayInvoiceFromTransaction.call(transaction: transaction, invoice: suggestion.target, fiscal_year: fiscal_year)
    end
  end
end

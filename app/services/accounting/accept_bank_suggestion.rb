# Books the suggestion MatchBankTransaction computes for a transaction.
# Returns the service result, or nil when there is no suggestion.
# `draft: true` (whoever cannot validate, and the automatic matches): the payment entry stays a draft and the line is "matched".
# A supplier payment as a draft is for a whole invoice in euros (see PayInvoiceFromTransaction); it is lettered when validated.
class Accounting::AcceptBankSuggestion
  FEES_LABEL = "Bank fees"

  def self.call(transaction:, draft: false)
    suggestion = Accounting::MatchBankTransaction.call(transaction: transaction)
    return unless suggestion

    fiscal_year = Accounting::FiscalYear.current

    case suggestion.kind
    when :payment_batch_debit
      proposal = suggestion.proposal
      (proposal.link ? Payments::LinkManualDebit : Payments::ConfirmDebit).call(batch: suggestion.target, user: Current.user, transaction: transaction, items: proposal.items)
    when :payment_return
      LightService::Context.make(transaction: transaction).tap { |ctx| ctx.fail!(I18n.t("payments.debit.errors.return_needs_reason")) } # a person gives the reason: Payments::RegisterReturn
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
      Accounting::BookInvoiceReceipt.call(transaction: transaction, invoice: suggestion.target, fiscal_year: fiscal_year, draft: draft, rounding: suggestion.rounding)
    when :supplier_invoices
      Accounting::PayInvoicesFromTransaction.call(transaction: transaction, invoices: suggestion.target, fiscal_year: fiscal_year, draft: draft)
    when :supplier_invoice
      Accounting::PayInvoiceFromTransaction.call(transaction: transaction, invoice: suggestion.target, fiscal_year: fiscal_year, draft: draft)
    end
  end
end

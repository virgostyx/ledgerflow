# Books a customer receipt matched to an invoice: bank / receivable (400000, with the partner)
# via the regular reconciliation, then marks the invoice paid. All or nothing.
# ponytail: exact amount only; partial payment / overpayment need allocation logic.
class Accounting::BookInvoiceReceipt
  extend LightService::Organizer

  def self.call(transaction:, invoice:, fiscal_year:)
    error = guard(transaction, invoice)
    return failure(transaction, error) if error

    result = nil
    ApplicationRecord.transaction do
      result = Accounting::ReconcileBankTransaction.call(
        transaction: transaction,
        account_id:  Accounting::Account.find_by!(code: "400000").id,
        fiscal_year: fiscal_year,
        label:       "Receipt #{invoice.invoice_number}",
        partner:     invoice.partner
      )
      invoice.pay! if result.success?
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    failure(transaction, "Error: #{e.message}")
  end

  def self.guard(tx, invoice)
    if tx.reconciled? || !tx.credit?                            then "Not a pending credit"
    elsif !invoice.customer? || !invoice.posted?                then "Invoice is not an open customer invoice"
    elsif tx.amount != invoice.total_incl_vat                   then "Amount does not match the invoice"
    end
  end

  def self.failure(tx, message)
    LightService::Context.make(transaction: tx).tap { |ctx| ctx.fail!(message) }
  end
  private_class_method :guard, :failure
end

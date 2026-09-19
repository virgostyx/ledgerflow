# Books a customer receipt matched to an invoice: bank / receivable (400000, with the partner)
# via the regular reconciliation. Partial payments are allowed up to the remaining balance; the invoice
# is marked paid once the balance reaches zero. All or nothing.
# ponytail: no overpayment handling (refused); one receipt = one invoice, no grouped payments.
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
        partner:     invoice.partner,
        source_type: "Accounting::InvoiceReceipt",
        source_id:   invoice.id
      )
      invoice.pay! if result.success? && invoice.remaining_amount.zero?
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    failure(transaction, "Error: #{e.message}")
  end

  def self.guard(tx, invoice)
    if tx.reconciled? || !tx.credit?                            then "Not a pending credit"
    elsif !invoice.customer? || !invoice.posted?                then "Invoice is not an open customer invoice"
    elsif tx.amount > invoice.remaining_amount                  then "Amount exceeds the invoice balance"
    end
  end

  def self.failure(tx, message)
    LightService::Context.make(transaction: tx).tap { |ctx| ctx.fail!(message) }
  end
  private_class_method :guard, :failure
end

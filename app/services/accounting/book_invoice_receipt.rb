# Books a customer receipt: bank / receivable (400000) via the regular reconciliation, each receivable line
# linked to its invoice and partner.
# - One invoice: partial payments leave it open, it is paid once the balance reaches zero; an overpayment is
#   booked in full and the excess stays as a credit balance for the partner on 400000.
# - Several invoices of one partner (grouped transfer): the amount must equal the sum of their balances.
# All or nothing.
# ponytail: no automatic allocation of a credit balance to other invoices; a grouped transfer must be exact.
class Accounting::BookInvoiceReceipt
  extend LightService::Organizer

  def self.call(transaction:, fiscal_year:, invoice: nil, invoices: nil)
    list  = (invoices || [ invoice ]).uniq
    error = guard(transaction, list)
    return failure(transaction, error) if error

    result = nil
    ApplicationRecord.transaction do
      result = Accounting::ReconcileBankTransaction.call(
        transaction: transaction,
        account_id:  Accounting::Account.find_by!(code: "400000").id,
        fiscal_year: fiscal_year,
        label:       "Receipt #{list.filter_map(&:invoice_number).join(', ')}".strip,
        allocations: allocations(transaction, list)
      )
      list.each { |i| i.pay! if i.remaining_amount.zero? } if result.success?
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    failure(transaction, "Error: #{e.message}")
  end

  def self.allocations(tx, list)
    list.one? ? [ [ list.first, tx.amount ] ] : list.map { |i| [ i, i.remaining_amount ] }
  end

  def self.guard(tx, list)
    if tx.reconciled? || !tx.credit?                              then "Not a pending credit"
    elsif list.any? { |i| !i.customer? || !i.posted? }            then "Invoice is not an open customer invoice"
    elsif list.map(&:partner_id).uniq.size > 1                    then "Invoices must belong to the same partner"
    elsif list.many? && list.sum(&:remaining_amount) != tx.amount then "Amount does not match the sum of the invoice balances"
    end
  end

  def self.failure(tx, message)
    LightService::Context.make(transaction: tx).tap { |ctx| ctx.fail!(message) }
  end
  private_class_method :allocations, :guard, :failure
end

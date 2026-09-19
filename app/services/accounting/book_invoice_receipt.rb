# Books a customer receipt: bank / receivable (400000) via the regular reconciliation, one receivable line per
# allocated invoice, linked to the invoice and its partner. The allocated amounts must add up to the transaction.
# - invoice:     the whole amount on one invoice (partial payment leaves it open; an overpayment stays as a credit
#                balance for the partner on 400000).
# - invoices:    a grouped transfer, each invoice settled for its remaining balance.
# - allocations: explicit [[invoice, amount], ...] chosen by the user.
# An invoice is marked paid once its balance reaches zero. All or nothing.
# ponytail: no automatic allocation of a credit balance to other invoices.
class Accounting::BookInvoiceReceipt
  extend LightService::Organizer

  def self.call(transaction:, fiscal_year:, invoice: nil, invoices: nil, allocations: nil)
    allocations = build_allocations(transaction, invoice, invoices, allocations)
    error = guard(transaction, allocations)
    return failure(transaction, error) if error

    list   = allocations.map(&:first)
    result = nil
    ApplicationRecord.transaction do
      result = Accounting::ReconcileBankTransaction.call(
        transaction: transaction,
        account_id:  Accounting::Account.find_by!(code: "400000").id,
        fiscal_year: fiscal_year,
        label:       "Receipt #{list.filter_map(&:invoice_number).join(', ')}".strip,
        allocations: allocations
      )
      list.each { |i| i.pay! if i.remaining_amount.zero? } if result.success?
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    failure(transaction, "Error: #{e.message}")
  end

  def self.build_allocations(tx, invoice, invoices, allocations)
    return allocations if allocations
    return invoices.uniq.map { |i| [ i, i.remaining_amount ] } if invoices

    [ [ invoice, tx.amount ] ]
  end

  def self.guard(tx, allocations)
    list = allocations.map(&:first)
    if tx.reconciled? || !tx.credit?                                 then "Not a pending credit"
    elsif allocations.empty?                                         then "Nothing to allocate"
    elsif list.any? { |i| !i.customer? || !i.posted? }               then "Invoice is not an open customer invoice"
    elsif list.uniq.size != list.size                                then "An invoice can only be allocated once"
    elsif list.map(&:partner_id).uniq.size > 1                       then "Invoices must belong to the same partner"
    elsif allocations.any? { |_, amount| amount <= 0 }               then "Allocated amounts must be positive"
    elsif allocations.sum { |_, amount| amount } != tx.amount        then "Allocated amounts must add up to the transaction amount"
    end
  end

  def self.failure(tx, message)
    LightService::Context.make(transaction: tx).tap { |ctx| ctx.fail!(message) }
  end
  private_class_method :build_allocations, :guard, :failure
end

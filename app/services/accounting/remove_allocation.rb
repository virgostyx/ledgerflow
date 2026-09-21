# Undoes one partial allocation. Invoices its lines had settled or partly settled are re-synced.
# A lettered group must be unlettered instead (which drops its allocations).
class Accounting::RemoveAllocation
  def self.call(allocation:)
    ctx = LightService::Context.make(allocation: allocation)
    lines = [ allocation.debit_line, allocation.credit_line ]
    return ctx.tap { |c| c.fail!("Remove the lettering first") } if lines.any?(&:lettering_id)

    ApplicationRecord.transaction do
      reopen_paid_invoices(lines)
      allocation.destroy!
      Accounting::SyncInvoiceStatus.call(lines)
    end
    ctx
  rescue StandardError => e
    ctx.tap { |c| c.fail!("Error: #{e.message}") }
  end

  # A fully allocated invoice is paid; once its allocation goes it is only partly (or not) paid again.
  def self.reopen_paid_invoices(lines)
    trade = lines.select { |l| Accounting::Actions::PayLetteredInvoices::TRADE_ACCOUNTS.include?(l.account.code) && l.open_amount.zero? }
    Accounting::Invoice.paid.where(journal_entry_id: trade.map(&:journal_entry_id)).find_each do |invoice|
      invoice.reopen! unless Accounting::PaymentBatchLine.active.exists?(invoice_id: invoice.id)
    end
  end
  private_class_method :reopen_paid_invoices
end

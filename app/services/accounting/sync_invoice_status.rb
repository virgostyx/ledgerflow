# Keeps open invoices in step with partial allocations on their payable/receivable line:
# fully allocated => paid, partly => partially_paid, not at all => posted.
class Accounting::SyncInvoiceStatus
  def self.call(lines)
    trade = lines.select { |l| Accounting::Actions::PayLetteredInvoices::TRADE_ACCOUNTS.include?(l.account.code) }
    Accounting::Invoice.where(journal_entry_id: trade.map(&:journal_entry_id), status: %i[posted partially_paid]).find_each do |invoice|
      line = trade.find { |l| l.journal_entry_id == invoice.journal_entry_id }
      if line.open_amount.zero?
        invoice.pay!
      elsif line.allocations.exists?
        invoice.part_pay! if invoice.posted?
      else
        invoice.release! if invoice.partially_paid?
      end
    end
  end
end

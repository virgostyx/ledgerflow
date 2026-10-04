# An invoice is settled once its own payable/receivable line (not its expense or VAT lines) is lettered.
class Accounting::Actions::PayLetteredInvoices
  extend LightService::Action

  expects :lines, :lettering

  TRADE_ACCOUNTS = [ Accounting::AccountCodes::CUSTOMERS, Accounting::AccountCodes::SUPPLIERS ].freeze

  # The entries whose invoices these lines settle: their own, and the entry of the line each one carries forward (F10): a line carried into the next fiscal year
  # stands for the invoice line of the year before.
  def self.entry_ids(lines)
    origins = Accounting::JournalEntryLine.where(id: lines.filter_map(&:origin_line_id)).pluck(:journal_entry_id)
    (lines.map(&:journal_entry_id) + origins).uniq
  end

  executed do |ctx|
    next if ctx[:settle] == false || !TRADE_ACCOUNTS.include?(ctx.lettering.account.code)

    Accounting::Invoice.where(status: %i[posted partially_paid]).where(journal_entry_id: entry_ids(ctx.lines)).find_each(&:pay!)
  rescue AASM::InvalidTransition, ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!("Could not mark invoice as paid: #{e.message}")
  end
end

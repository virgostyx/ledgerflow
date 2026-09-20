# An invoice is settled once its own payable/receivable line (not its expense or VAT lines) is lettered.
class Accounting::Actions::PayLetteredInvoices
  extend LightService::Action

  expects :lines, :lettering

  TRADE_ACCOUNTS = [ Accounting::AccountCodes::CUSTOMERS, Accounting::AccountCodes::SUPPLIERS ].freeze

  executed do |ctx|
    next unless TRADE_ACCOUNTS.include?(ctx.lettering.account.code)

    Accounting::Invoice.posted.where(journal_entry_id: ctx.lines.map(&:journal_entry_id)).find_each(&:pay!)
  rescue AASM::InvalidTransition, ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!("Could not mark invoice as paid: #{e.message}")
  end
end

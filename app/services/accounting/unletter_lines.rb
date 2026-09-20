# Undoes a lettering. Invoices that lettering had settled go back to posted, except those also tied to a payment
# batch (they were paid for real, the lettering only matched the entries). All or nothing.
class Accounting::UnletterLines
  extend LightService::Organizer

  def self.call(lettering:)
    ctx = LightService::Context.make(lettering: lettering)
    ApplicationRecord.transaction do
      reopen_invoices(lettering)
      lettering.destroy!
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  def self.reopen_invoices(lettering)
    return unless Accounting::Actions::PayLetteredInvoices::TRADE_ACCOUNTS.include?(lettering.account.code)

    entry_ids = lettering.lines.pluck(:journal_entry_id)
    Accounting::Invoice.paid.where(journal_entry_id: entry_ids).find_each do |invoice|
      invoice.reopen! unless Accounting::PaymentBatchLine.active.exists?(invoice_id: invoice.id)
    end
  end
  private_class_method :reopen_invoices
end

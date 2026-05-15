class Accounting::PostInvoice
  extend LightService::Organizer

  def self.call(invoice:)
    result = nil
    ApplicationRecord.transaction do
      result = with(invoice: invoice).reduce(
        Accounting::Actions::ValidateInvoice,
        Accounting::Actions::ComputeInvoiceTotals,
        Accounting::Actions::AssignInvoiceNumber,
        Accounting::Actions::GenerateInvoiceJournalEntry,
        Accounting::Actions::UpdateInvoiceStatus
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(invoice: invoice)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end

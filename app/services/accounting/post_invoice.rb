class Accounting::PostInvoice
  extend LightService::Organizer

  def self.call(invoice:)
    result = nil
    ApplicationRecord.transaction do
      result = with(invoice: invoice).reduce(
        Accounting::Actions::ValidateInvoice,
        Accounting::Actions::ValidateInvoiceCoding,
        Accounting::Actions::ComputeInvoiceTotals,
        Accounting::Actions::ValidateInvoiceFourEyes,
        Accounting::Actions::ValidateCreditNoteAmount,
        Accounting::Actions::AssignInvoiceNumber,
        Accounting::Actions::GenerateInvoiceJournalEntry,
        Accounting::Actions::UpdateInvoiceStatus,
        Accounting::Actions::PayFromCash
      )
      raise ActiveRecord::Rollback if result.failure?

      Accounting::RememberSupplierDefaults.call(invoice: invoice)
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(invoice: invoice)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end

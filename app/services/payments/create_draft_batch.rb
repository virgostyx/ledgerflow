class Payments::CreateDraftBatch
  extend LightService::Organizer

  def self.call(invoice_ids:, bank_account:, requested_execution_date:)
    result = nil
    ApplicationRecord.transaction do
      result = with(
        invoice_ids: invoice_ids,
        bank_account: bank_account,
        requested_execution_date: requested_execution_date
      ).reduce(
        Payments::Actions::ValidateBatchInvoices,
        Payments::Actions::CreatePaymentBatchRecord
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(invoice_ids: invoice_ids)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end

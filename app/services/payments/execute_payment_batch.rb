class Payments::ExecutePaymentBatch
  extend LightService::Organizer

  def self.call(payment_batch:)
    unless payment_batch.generated?
      ctx = LightService::Context.make(payment_batch: payment_batch)
      ctx.fail!(I18n.t("payments.errors.batch_not_generated"))
      return ctx
    end

    result = nil
    ApplicationRecord.transaction do
      result = with(payment_batch: payment_batch).reduce(
        Payments::Actions::CreateSettlementJournalEntry,
        Payments::Actions::MarkInvoicesPaid,
        Payments::Actions::MarkBatchExecuted
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(payment_batch: payment_batch)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end

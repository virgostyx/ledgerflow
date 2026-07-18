class Payments::GenerateSepaFile
  extend LightService::Organizer

  def self.call(payment_batch:)
    unless payment_batch.draft?
      ctx = LightService::Context.make(payment_batch: payment_batch)
      ctx.fail!(I18n.t("payments.errors.batch_not_draft"))
      return ctx
    end

    result = nil
    ApplicationRecord.transaction do
      result = with(payment_batch: payment_batch).reduce(
        Payments::Actions::BuildSepaXml,
        Payments::Actions::PersistGeneratedFile
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

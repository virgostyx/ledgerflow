class Peppol::SendInvoice
  extend LightService::Organizer

  def self.call(invoice:)
    unless invoice.posted?
      ctx = LightService::Context.make(invoice: invoice)
      ctx.fail!(I18n.t("peppol.errors.invoice_not_posted"))
      return ctx
    end

    result = nil
    ApplicationRecord.transaction do
      result = with(invoice: invoice)
        .reduce(
          Peppol::Actions::BuildUblXml,
          Peppol::Actions::SendToDigiteal,
          Peppol::Actions::HandleDeliveryStatus
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

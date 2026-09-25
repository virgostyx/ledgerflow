class Peppol::SendInvoice
  extend LightService::Organizer

  def self.call(invoice:)
    result = nil
    ApplicationRecord.transaction do
      result = with(invoice: invoice)
        .reduce(
          Peppol::Actions::ValidateSendable,
          Peppol::Actions::BuildUblXml,
          Peppol::Actions::SendViaAccessPoint,
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

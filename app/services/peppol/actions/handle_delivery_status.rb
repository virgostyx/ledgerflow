class Peppol::Actions::HandleDeliveryStatus
  extend LightService::Action

  expects :invoice, :peppol_id

  executed do |ctx|
    ctx.invoice.update!(peppol_id: ctx.peppol_id, peppol_status: :queued)
    ctx.invoice.peppol_events.create!(kind: :sent, message: "Handed to the Access Point (message #{ctx.peppol_id})")
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!("Status update error: #{e.message}")
  end
end

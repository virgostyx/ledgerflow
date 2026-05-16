class Peppol::Actions::HandleDeliveryStatus
  extend LightService::Action

  expects :invoice, :peppol_id

  executed do |ctx|
    ctx.invoice.update!(peppol_id: ctx.peppol_id, peppol_status: :queued)
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!("Status update error: #{e.message}")
  end
end

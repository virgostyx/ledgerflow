class Peppol::Actions::HandleDeliveryStatus
  extend LightService::Action

  expects :invoice, :peppol_id

  executed do |ctx|
    ctx.invoice.update!(peppol_id: ctx.peppol_id, peppol_status: :queued)
    ctx.invoice.peppol_events.create!(kind: :sent, message: "Handed to the Access Point (message #{ctx.peppol_id})")
    record_message(ctx)
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!("Status update error: #{e.message}")
  end

  # The message as sent, kept with its XML (F06 step 1): its delivery is followed on it.
  def self.record_message(ctx)
    message = Accounting::PeppolMessage.outbound.find_or_initialize_by(message_id: ctx.peppol_id)
    message.update!(invoice: ctx.invoice, status: :queued, problems: [], sender_id: ctx[:sender], receiver_id: ctx[:receiver], xml: ctx[:ubl_xml],
                    document_type: ctx.invoice.credit_note? ? :credit_note : :invoice, occurred_at: Time.current)
  end
end

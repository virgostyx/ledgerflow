# Hands the document to the Access Point. A technical error (not reachable, a server error) does not fail the sending: the message waits as
# "retrying" and Peppol::SendRetryJob tries again (three attempts in all, with a longer wait each time). A refusal of the document is a failure.
class Peppol::Actions::SendViaAccessPoint
  extend LightService::Action

  expects  :invoice, :ubl_xml, :access_point, :sender, :receiver
  promises :peppol_id

  executed do |ctx|
    ctx.peppol_id = ctx.access_point.send_document(xml: ctx.ubl_xml, sender: ctx.sender, receiver: ctx.receiver, document_id: ctx.invoice.invoice_number)
  rescue Peppol::AccessPoint::TemporaryError => e
    ctx.peppol_id = nil # nothing was handed over (the promise is kept)
    ctx[:retrying] = schedule_retry(ctx, e.message)
    ctx.skip_remaining!
  rescue Peppol::AccessPoint::Error => e
    ctx.fail!(e.message)
  end

  def self.schedule_retry(ctx, reason)
    message = Accounting::PeppolMessage.outbound.find_or_initialize_by(invoice_id: ctx.invoice.id, status: :retrying)
    message.message_id ||= "pending-#{SecureRandom.hex(8)}"
    message.update!(invoice: ctx.invoice, status: :retrying, sender_id: ctx.sender, receiver_id: ctx.receiver, xml: ctx.ubl_xml, attempts: 1, problems: [ reason ],
                    document_type: ctx.invoice.credit_note? ? :credit_note : :invoice, occurred_at: Time.current, next_attempt_at: Time.current + Peppol::SendRetryJob::WAITS.first)
    Peppol::SendRetryJob.set(wait: Peppol::SendRetryJob::WAITS.first).perform_later(message.id, message.entity_id)
    true
  end
  private_class_method :schedule_retry
end

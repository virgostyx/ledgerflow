# F06 step 5: tries again to hand an invoice to the Access Point after a technical error. Three attempts in all (the first was made when the
# user asked), a longer wait each time; a refusal of the document is not retried, and the same document is sent (it was validated before).
# At the end the message and the invoice are "failed", with the reason, and can be sent again by a person.
class Peppol::SendRetryJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 3
  WAITS = [ 1.minute, 5.minutes ].freeze # before the 2nd and the 3rd attempt

  def perform(message_id, entity_id)
    ActsAsTenant.with_tenant(Entity.find(entity_id)) do
      message = Accounting::PeppolMessage.outbound.find_by(id: message_id, status: :retrying) or next
      invoice = message.invoice
      access_point = Peppol::AccessPoint.for(invoice.entity)
      begin
        peppol_id = access_point.send_document(xml: message.xml, sender: message.sender_id, receiver: message.receiver_id, document_id: invoice.invoice_number)
        Peppol::Actions::HandleDeliveryStatus.accept!(invoice: invoice, peppol_id: peppol_id, xml: message.xml, sender: message.sender_id, receiver: message.receiver_id)
      rescue Peppol::AccessPoint::TemporaryError => e
        again(message, invoice, e.message)
      rescue Peppol::AccessPoint::Error => e
        give_up(message, invoice, e.message)
      end
    end
  end

  private

  # `made`: the attempts made so far, this one included.
  def again(message, invoice, reason)
    made = message.attempts + 1
    return give_up(message, invoice, "#{reason} (#{MAX_ATTEMPTS} attempts)") if made >= MAX_ATTEMPTS

    wait = WAITS.fetch(made - 1)
    message.update!(attempts: made, problems: [ reason ], next_attempt_at: Time.current + wait)
    self.class.set(wait: wait).perform_later(message.id, message.entity_id)
  end

  def give_up(message, invoice, reason)
    ApplicationRecord.transaction do
      message.update!(status: :failed, problems: [ reason ], next_attempt_at: nil)
      invoice.update!(peppol_status: :failed)
      invoice.peppol_events.create!(kind: :failed, message: reason)
    end
  end
end

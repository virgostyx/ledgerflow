# F06 step 1: a document that reaches an entity through Peppol. The message is recorded first (identifier, parties, type, process, XML), under
# its own identifier: delivered twice, it is one record (the Access Point's message id, else the digest of the XML). Then Peppol::ProcessMessage
# works on it, and never raises: what cannot be worked on is kept for a person, with the reasons. Called inside the tenant of the entity.
# => ctx[:message], ctx[:invoice], ctx[:duplicate]
class Peppol::ReceiveMessage
  def self.call(event:)
    xml = event.xml.to_s
    id = event.message_id.presence || "sha256:#{Digest::SHA256.hexdigest(xml)}"
    known = Accounting::PeppolMessage.inbound.find_by(message_id: id)
    return outcome(known, duplicate: true) if known

    message = begin
      store(event, id, xml)
    rescue ActiveRecord::RecordNotUnique
      return outcome(Accounting::PeppolMessage.inbound.find_by!(message_id: id), duplicate: true)
    end
    Peppol::ProcessMessage.call(message: message)
    outcome(message.reload, duplicate: false)
  end

  def self.store(event, id, xml)
    described = Accounting::PeppolMessage.describe(xml)
    Accounting::PeppolMessage.create!(direction: :inbound, message_id: id, receiver_id: event.receiver, status: :received, xml: xml,
                                      sender_id: event.sender.presence || described[:sender_id], document_type: described[:document_type], process: described[:process])
  end

  def self.outcome(message, duplicate:) = LightService::Context.make(message: message, invoice: message.invoice, duplicate: duplicate)
  private_class_method :store, :outcome
end

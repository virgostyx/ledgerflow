# F06 step 6: fetches the XML of a received document the Access Point announced without it (a webhook that only gives identifiers), keeps it on the
# message, and works on the message. A technical error is raised to the caller (the job tries again); anything else puts the message in review.
# => the message
class Peppol::FetchReceived
  def self.call(message:)
    return message if message.xml.present?

    xml = Peppol::AccessPoint.for(message.entity).fetch_received(message.remote_id)
    described = Accounting::PeppolMessage.describe(xml)
    message.update!(xml: xml, document_type: described[:document_type], process: described[:process], sender_id: message.sender_id || described[:sender_id], problems: [])
    Peppol::ProcessMessage.call(message: message)
  rescue Peppol::AccessPoint::TemporaryError
    raise
  rescue Peppol::AccessPoint::Error, NotImplementedError => e
    message.update!(status: :needs_review, problems: [ e.message ])
    message
  end
end

class Peppol::Actions::HandleDeliveryStatus
  extend LightService::Action

  expects :invoice, :peppol_id

  executed do |ctx|
    accept!(invoice: ctx.invoice, peppol_id: ctx.peppol_id, xml: ctx[:ubl_xml], sender: ctx[:sender], receiver: ctx[:receiver])
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!("Status update error: #{e.message}")
  end

  # The Access Point took the document: the invoice is queued, and the message as sent is kept with its XML (F06) and followed. Also what a
  # retry does when it finally gets through (the message that was waiting becomes the sent one).
  def self.accept!(invoice:, peppol_id:, xml:, sender:, receiver:)
    invoice.update!(peppol_id: peppol_id, peppol_status: :queued)
    invoice.peppol_events.create!(kind: :sent, message: "Handed to the Access Point (message #{peppol_id})")
    message = Accounting::PeppolMessage.outbound.find_by(invoice_id: invoice.id, status: :retrying) || Accounting::PeppolMessage.outbound.find_or_initialize_by(message_id: peppol_id)
    message.update!(message_id: peppol_id, invoice: invoice, status: :queued, problems: [], sender_id: sender, receiver_id: receiver, xml: xml.presence || message.xml,
                    document_type: invoice.credit_note? ? :credit_note : :invoice, occurred_at: Time.current, next_attempt_at: nil)
    keep_in_document_store(message, invoice)
    message
  end

  # The XML as sent, in the document store (F03), linked to the invoice. Best effort, like on reception: the message holds the XML anyway.
  def self.keep_in_document_store(message, invoice)
    return if message.document_id || message.xml.blank?

    result = Accounting::UploadDocument.call(io: StringIO.new(message.xml), filename: "#{invoice.invoice_number.to_s.tr('^A-Za-z0-9._-', '_')}.xml", user: nil, origin: :peppol,
                                             kind: invoice.credit_note? ? :credit_note : :sales_invoice, details: { "peppol_message_id" => message.message_id })
    document = result.success? ? result[:document] : result[:existing]
    return message.update!(note: [ message.note, "Not kept in the document store: #{result.message}" ].compact.join(" · ")) unless document

    message.update!(document: document)
    Accounting::LinkDocument.call(document: document, target: invoice, user: nil) if result.success?
  end
  private_class_method :keep_in_document_store
end

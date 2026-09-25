# A generic Access Point that lives in the application, for development and test (Entity refuses it in production).
# Nothing leaves the process. What happens to a document depends on the receiver identifier:
# - ending with -UNREGISTERED: the participant is not registered, the send is refused;
# - ending with -FAILED: the delivery fails (reported by a job, after the send has returned, like a webhook);
# - ending with -SLOW: the document stays queued until `bin/rails peppol:simulator:deliver[message_id]`;
# - anything else: delivered.
# It proves that OUR side works; it says nothing about how a real Access Point behaves.
class Peppol::AccessPoint::Simulator < Peppol::AccessPoint::Base
  UNREGISTERED = "-UNREGISTERED".freeze
  FAILED       = "-FAILED".freeze
  SLOW         = "-SLOW".freeze

  def send_document(xml:, sender:, receiver:, document_id:)
    ensure_well_formed!(xml)
    raise Peppol::AccessPoint::Error, "Receiver #{receiver.inspect} is not a Peppol participant identifier" unless Peppol::ParticipantId.valid?(receiver)
    raise Peppol::AccessPoint::Error, "Receiver #{receiver} is not registered on the Peppol network" unless registered?(receiver)

    "SIM-#{SecureRandom.hex(6)}".tap { |message_id| report(message_id, receiver) }
  end

  def registered?(participant_id)
    Peppol::ParticipantId.valid?(participant_id) && !participant_id.end_with?(UNREGISTERED)
  end

  # Same contract as a real webhook: a JSON body signed with the webhook token of the entity, so that the webhook
  # endpoint can be tried by hand in development.
  def parse_webhook(headers:, body:)
    unless signature_valid?(body, headers["X-Simulator-Signature"], entity.peppol_webhook_token)
      raise Peppol::AccessPoint::InvalidSignature, "Bad signature"
    end

    payload = parsed_json(body)
    kind = payload["event"].to_s.to_sym
    return [] unless %i[delivered failed received].include?(kind)

    [ Peppol::Event.new(kind: kind, message_id: payload["message_id"], receiver: payload["receiver"], xml: payload["xml"], error: payload["error"]) ]
  end

  # Plays what a real Access Point does when a supplier sends us an invoice: an event routed by our identifier.
  def simulate_incoming
    raise Peppol::AccessPoint::Error, "Set the Peppol identifier of the entity first" if entity.peppol_participant_id.blank?

    Peppol::HandleEvent.call(event: Peppol::Event.new(kind: :received, receiver: entity.peppol_participant_id, xml: sample_invoice))
  end

  private

  def sample_invoice
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
               xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
               xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>SIM-#{Time.current.strftime('%Y%m%d%H%M%S')}</cbc:ID>
        <cbc:IssueDate>#{Date.current}</cbc:IssueDate>
        <cbc:DueDate>#{30.days.from_now.to_date}</cbc:DueDate>
        <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
        <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
        <cac:AccountingSupplierParty><cac:Party>
          <cac:PartyName><cbc:Name>Simulated Supplier</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme><cbc:CompanyID>BE0123456749</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>
        </cac:Party></cac:AccountingSupplierParty>
        <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount></cac:TaxTotal>
        <cac:LegalMonetaryTotal>
          <cbc:TaxExclusiveAmount currencyID="EUR">100.00</cbc:TaxExclusiveAmount>
          <cbc:TaxInclusiveAmount currencyID="EUR">121.00</cbc:TaxInclusiveAmount>
        </cac:LegalMonetaryTotal>
      </Invoice>
    XML
  end

  def ensure_well_formed!(xml)
    Nokogiri::XML(xml) { |config| config.strict }
  rescue Nokogiri::XML::SyntaxError => e
    raise Peppol::AccessPoint::Error, "The document is not well-formed XML: #{e.message}"
  end

  def report(message_id, receiver)
    return if receiver.end_with?(SLOW)

    if receiver.end_with?(FAILED)
      Peppol::SimulatorDeliveryJob.perform_later(message_id, "failed", "Delivery failed (simulated)")
    else
      Peppol::SimulatorDeliveryJob.perform_later(message_id, "delivered", nil)
    end
  end
end

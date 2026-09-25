# UNVALIDATED: written from memory of a public API and never checked against the Digiteal documentation or a sandbox
# account (the paths, the JSON fields, the webhook events and the signature header are all assumptions). Do not
# rely on it in production before it has been confronted with the real API.
class Peppol::AccessPoint::Digiteal < Peppol::AccessPoint::Base
  def self.credential_fields
    [
      { key: "api_key",        label: "API key",        required: true, secret: true },
      { key: "webhook_secret", label: "Webhook secret", required: true, secret: true }
    ]
  end

  def send_document(xml:, sender:, receiver:, document_id:)
    api_key = credential("api_key") or raise Peppol::AccessPoint::NotConfigured, "The Digiteal API key is not set"

    response = connection.post("/api/invoices") do |request|
      request.headers["Authorization"] = "Bearer #{api_key}"
      request.headers["Content-Type"]  = "application/xml"
      request.body = xml
    end

    JSON.parse(response.body)["id"].presence or raise Peppol::AccessPoint::Error, "Digiteal returned no document id"
  rescue Faraday::Error => e
    raise Peppol::AccessPoint::Error, "Digiteal API error: #{e.message}"
  rescue JSON::ParserError => e
    raise Peppol::AccessPoint::Error, "Invalid Digiteal response: #{e.message}"
  end

  def parse_webhook(headers:, body:)
    unless signature_valid?(body, headers["X-Peppol-Signature"], credential("webhook_secret"))
      raise Peppol::AccessPoint::InvalidSignature, "Bad signature"
    end

    payload = parsed_json(body)
    case payload["event"]
    when "INVOICE_DELIVERED" then delivery_events(payload)
    when "INVOICE_RECEIVED"  then [ Peppol::Event.new(kind: :received, xml: payload["ubl_xml"], receiver: payload["receiver"]) ]
    else []
    end
  end

  private

  def delivery_events(payload)
    kind = { "DELIVERED" => :delivered, "FAILED" => :failed }[payload["status"].to_s.upcase]
    kind ? [ Peppol::Event.new(kind: kind, message_id: payload["document_id"], error: payload["error"]) ] : []
  end

  def connection
    Faraday.new(url: DIGITEAL_API_URL) do |f|
      f.request :retry, max: 2, interval: 0.5
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
  end
end

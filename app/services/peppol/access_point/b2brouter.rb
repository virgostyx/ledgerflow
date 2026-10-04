# B2Brouter (https://docs.b2brouter.net/en/developers/). Written from its documentation and a real import of one of our
# UBL documents in its sandbox; NOT yet run end to end: the send step, the webhook payloads and the directory lookup follow
# the documentation only. Received invoices are not handled yet (their webhook is not documented in what was read).
class Peppol::AccessPoint::B2brouter < Peppol::AccessPoint::Base
  API_VERSION = "2026-03-02".freeze
  LIST_PAGE = 100
  SIGNATURE_TOLERANCE = 5.minutes.to_i # seconds a webhook's timestamp may differ from ours
  # Sandbox scenarios (docs.b2brouter.net/en/developers/testing/sandbox): success = sent, registered; refused by the buyer =
  # sent, registered, refused; no receiver = sent, error. "registered" is the Peppol network accepting the message.
  DELIVERED_STATES = %w[registered closed accepted read paid].freeze
  FAILED_STATES    = %w[error refused invalid].freeze
  # An invoice in one of these states has already been handed over: importing the same number again means a previous try
  # got through (for instance the answer was lost), not that a new document is being sent.
  SETTLED_STATES = (%w[sent] + DELIVERED_STATES + %w[refused]).freeze

  def self.requires_buyer_email? = true

  def self.credential_fields
    [
      { key: "api_key",        label: "API key",        required: true, secret: true },
      { key: "account_id",     label: "Account ID",     required: true, secret: false },
      { key: "webhook_secret", label: "Webhook secret", required: true, secret: true }
    ]
  end

  # The sandbox keys start with test_ (docs.b2brouter.net/en/developers/testing/sandbox).
  def test_environment? = credential("api_key").to_s.start_with?("test_")

  # Two calls, as documented: import the file, then send the imported invoice.
  def send_document(xml:, sender:, receiver:, document_id:)
    api_key, account_id = credential("api_key"), credential("account_id")
    raise Peppol::AccessPoint::NotConfigured, "The B2Brouter API key and account ID are not set" unless api_key && account_id

    begin
      id = import(xml, account_id)
    rescue Peppol::AccessPoint::Error => e
      raise unless e.message.include?("already been taken")

      existing = find_by_number(account_id, document_id) or raise
      return existing["id"].to_s if SETTLED_STATES.include?(existing["state"]) # an earlier try got through: do not send it twice

      discard(existing["id"]) # left as new or error by an earlier try, with an older content
      id = import(xml, account_id)
    end
    begin
      request(:post, "/invoices/send_invoice/#{id}")
    rescue Peppol::AccessPoint::Error
      discard(id) # an invoice left imported would make its number "already taken" on the next try
      raise
    end
    id.to_s
  end

  # The directory needs the country (only known for the Belgian enterprise-number scheme) and the bare value, without
  # the scheme: /directory/be/0214596464 (checked against the real API; "0208:0214596464" is answered 404).
  def registered?(participant_id)
    return unless participant_id.to_s.start_with?("#{Peppol::ParticipantId::BELGIAN_SCHEME}:")

    connection.get("/directory/be/#{participant_id.split(":", 2).last}") { |r| headers(r) }
    true
  rescue Faraday::ResourceNotFound
    false
  rescue Faraday::Error
    nil
  end

  def fetches_received? = true

  # The UBL BIS 3 of a received invoice (GET /invoices/{id}/as/xml.ubl.invoice.bis3: the same route as for an issued one).
  def fetch_received(remote_id)
    response = connection.get("/invoices/#{Integer(remote_id)}/as/xml.ubl.invoice.bis3") { |r| headers(r); r.headers["Accept"] = "*/*" }
    response.body.to_s
  rescue Faraday::TooManyRequestsError, Faraday::ServerError, Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise Peppol::AccessPoint::TemporaryError, "B2Brouter cannot be reached: #{e.message}"
  rescue Faraday::Error, ArgumentError => e
    raise Peppol::AccessPoint::Error, "B2Brouter: the received document #{remote_id} cannot be fetched (#{e.message})"
  end

  # The received invoices of the account, newest first, from a date on (GET /accounts/{id}/invoices?type=ReceivedInvoice), all the pages.
  def list_received(since: nil)
    account_id = credential("account_id") or raise Peppol::AccessPoint::NotConfigured, "The B2Brouter account ID is not set"
    found = []
    offset = 0
    loop do
      params = { type: "ReceivedInvoice", limit: LIST_PAGE, offset: offset }
      params[:date_from] = since.to_date.iso8601 if since
      page = request(:get, "/accounts/#{account_id}/invoices", params: params)["invoices"].to_a
      found.concat(page.map { |i| { message_id: "b2brouter-#{i['id']}", remote_id: i["id"].to_s, number: i["number"], date: i["date"] } })
      break if page.size < LIST_PAGE

      offset += LIST_PAGE
    end
    found
  end

  # X-B2Brouter-Signature: "t=<unix time>,s=<hex HMAC-SHA256 of "<t>.<raw body>" with the webhook secret>"
  def parse_webhook(headers:, body:)
    verify_signature!(headers["X-B2Brouter-Signature"], body)

    payload = parsed_json(body)
    return received_events(payload, body) if payload["code"] == "received_invoice.created"
    return [] unless payload["code"] == "issued_invoice.state_change"

    state = payload.dig("data", "state").to_s
    kind = if DELIVERED_STATES.include?(state) then :delivered
    elsif FAILED_STATES.include?(state) then :failed
    end
    return [] unless kind

    [ Peppol::Event.new(kind: kind, message_id: payload.dig("data", "invoice_id").to_s, error: payload.dig("data", "notes").presence, raw: body) ]
  end

  private

  # A received invoice is announced by its identifiers only (invoice_id, account_id, state): the document is fetched afterwards. An event about
  # another account than the one set up for the entity is not ours.
  def received_events(payload, body)
    data = payload["data"].to_h
    return [] if data["invoice_id"].blank? || (credential("account_id") && data["account_id"].to_s != credential("account_id").to_s)

    [ Peppol::Event.new(kind: :received, message_id: "b2brouter-#{data['invoice_id']}", remote_id: data["invoice_id"].to_s, raw: body) ]
  end

  def import(xml, account_id)
    imported = request(:post, "/accounts/#{account_id}/invoices/import", params: { send_after_import: false },
                                                                        body: "data:text/xml;name=invoice.xml;base64,#{Base64.strict_encode64(xml)}",
                                                                        content_type: "application/octet-stream")
    imported.dig("invoice", "id").presence or raise Peppol::AccessPoint::Error, "B2Brouter returned no invoice id"
  end

  def find_by_number(account_id, number)
    request(:get, "/accounts/#{account_id}/invoices", params: { number: number, limit: 5 })["invoices"].to_a.find { |i| i["number"] == number }
  end

  # The timestamp is part of what is signed: a call older than the tolerance is refused, so that a signed message cannot be replayed later.
  def verify_signature!(header, body)
    parts = header.to_s.split(",").filter_map { |p| p.split("=", 2) if p.include?("=") }.to_h
    secret = credential("webhook_secret")
    ok = secret && parts["t"] && parts["s"] &&
         ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest("SHA256", secret, "#{parts['t']}.#{body}"), parts["s"])
    raise Peppol::AccessPoint::InvalidSignature, "Bad signature" unless ok
    raise Peppol::AccessPoint::InvalidSignature, "Stale timestamp" if (Time.now.to_i - parts["t"].to_i).abs > SIGNATURE_TOLERANCE
  end

  def request(verb, path, params: nil, body: nil, content_type: nil)
    response = connection.run_request(verb, path, body, nil) do |r|
      headers(r)
      r.headers["Content-Type"] = content_type if content_type
      r.params.update(params) if params
    end
    response.body.present? ? JSON.parse(response.body) : {}
  rescue Faraday::TooManyRequestsError, Faraday::ServerError => e
    raise Peppol::AccessPoint::TemporaryError, "B2Brouter: #{api_message(e.response) || e.message}"
  rescue Faraday::ClientError => e
    raise Peppol::AccessPoint::Error, "B2Brouter: #{api_message(e.response) || e.message}"
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise Peppol::AccessPoint::TemporaryError, "B2Brouter cannot be reached: #{e.message}"
  rescue Faraday::Error, JSON::ParserError => e
    raise Peppol::AccessPoint::Error, "B2Brouter API error: #{e.message}"
  end

  def discard(id)
    request(:delete, "/invoices/#{id}")
  rescue Peppol::AccessPoint::Error
    nil
  end

  def api_message(response)
    body = JSON.parse(response[:body].to_s)
    body.dig("error", "message") || Array(body["errors"]).join(", ").presence
  rescue JSON::ParserError, TypeError
    nil
  end

  def headers(request)
    request.headers["X-B2B-API-Key"]     = credential("api_key")
    request.headers["X-B2B-API-Version"] = API_VERSION
    request.headers["Accept"]            = "application/json"
  end

  def connection
    Faraday.new(url: B2BROUTER_API_URL) do |f|
      f.request :retry, max: 2, interval: 0.5, methods: %i[get]
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
  end
end

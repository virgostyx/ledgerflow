require "net/http"
require "open3"
require "tempfile"
require Rails.root.join("tools/ledger-verify/lib/ledger_verify/verifier")

# B03c étape 3: the timestamp (RFC 3161) of an anchor. Only its fingerprint (the SHA-256 of the anchor) is sent to the authority the owner configured; the answer is checked
# against the certificate the owner gave for it (what the authority signs is not taken on its word), and kept in the anchor, once. An authority that does not answer leaves a
# message in the anchor and nothing else: the anchor stands without, the certificate says so, and a job tries again.
#
# => :off (nothing configured), :already (it has a token), :granted, :unavailable (no answer) or :rejected (an answer that does not verify)
module Ledger::Timestamping
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15

  def self.call(anchor, transport: default_transport)
    entity = ActsAsTenant.current_tenant
    url = entity.timestamp_authority_url.to_s
    return :off unless configured?(entity)
    return :already if anchor.timestamp_token.present?

    response = transport.call(url, query_for(anchor.anchor_hash))
    ok, detail = LedgerVerify::Verifier.send(:verify_token, Base64.strict_encode64(response), anchor.anchor_hash, entity.timestamp_authority_ca)
    return reject(anchor, detail) unless ok

    anchor.update_columns(timestamp_token: Base64.strict_encode64(response), timestamp_authority: url, timestamped_at: time_of(response), timestamp_error: nil, updated_at: Time.current)
    :granted
  rescue IOError, SystemCallError, Timeout::Error, SocketError, Net::HTTPError, OpenSSL::SSL::SSLError => e
    anchor.update_columns(timestamp_error: "the authority does not answer: #{e.class}: #{e.message}".first(250), updated_at: Time.current)
    :unavailable
  end

  # The anchors that have no token yet, for each company that has an authority configured (an hourly job).
  def self.retry_pending(transport: default_transport)
    Entity.where.not(timestamp_authority_url: [ nil, "" ]).find_each do |entity|
      next unless entity.feature?(:b03c)

      ActsAsTenant.with_tenant(entity) { Ledger::Anchor.where(timestamp_token: nil).chronological.find_each { |anchor| call(anchor, transport: transport) } }
    end
  end

  def self.configured?(entity) = entity.timestamp_authority_url.to_s.match?(%r{\Ahttps?://}i) && entity.timestamp_authority_ca.present?

  def self.default_transport
    lambda do |url, query|
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      reply = http.post(uri.request_uri, query, "Content-Type" => "application/timestamp-query", "Accept" => "application/timestamp-reply")
      raise Net::HTTPError.new("the authority answered #{reply.code}", reply) unless reply.is_a?(Net::HTTPSuccess)

      reply.body.b
    end
  end

  def self.query_for(digest_hex)
    output, _error, status = Open3.capture3("openssl", "ts", "-query", "-digest", digest_hex, "-sha256", "-cert")
    raise IOError, "openssl cannot make the query" unless status.success?

    output.b
  end
  private_class_method :query_for

  def self.reject(anchor, detail)
    anchor.update_columns(timestamp_error: detail.to_s.first(250), updated_at: Time.current)
    :rejected
  end
  private_class_method :reject

  def self.time_of(response)
    Tempfile.create([ "reply", ".tsr" ]) do |file|
      file.binmode.write(response)
      file.flush
      text, = Open3.capture3("openssl", "ts", "-reply", "-in", file.path, "-text")
      Time.zone.parse(text[/Time stamp: (.+)$/, 1].to_s) || Time.current
    end
  end
  private_class_method :time_of
end

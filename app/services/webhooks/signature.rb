# F13c: the signature of a delivery: HMAC-SHA256 of "<timestamp>.<body>" with the secret of the subscription, in the header
# `X-LedgerFlow-Signature: t=<timestamp>,v1=<hex>` (one `v1` per secret that signs: two for a day after a rotation). The receiver recomputes it from the
# raw body, compares in constant time, and refuses a timestamp that is too old, which is what stops a captured delivery from being sent again.
module Webhooks::Signature
  HEADER = "X-LedgerFlow-Signature".freeze
  TOLERANCE = 5.minutes

  def self.sign(secret, timestamp, body) = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")

  def self.header(secrets, body, timestamp: Time.now.to_i)
    "t=#{timestamp}," + Array(secrets).map { |secret| "v1=#{sign(secret, timestamp, body)}" }.join(",")
  end

  # What a receiver does (the test receiver of the specs and docs/api/webhooks.md do exactly this).
  def self.verify(secret, header, body, tolerance: TOLERANCE, now: Time.now.to_i)
    parts = header.to_s.split(",").map { |p| p.split("=", 2) }
    timestamp = parts.find { |k, _| k == "t" }&.last.to_i
    return false if timestamp.zero? || (now - timestamp).abs > tolerance

    expected = sign(secret, timestamp, body)
    parts.select { |k, _| k == "v1" }.any? { |_, signature| ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected) }
  end
end

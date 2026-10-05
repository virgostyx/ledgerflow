require "resolv"
require "ipaddr"

# F13c: a webhook is a request the server makes where it is told to: it must never be turned on the network behind it (SSRF). https only (http for a
# test setup, off by default), no address that is private, loopback, link-local or otherwise not public, no credentials in the URL. The name is resolved
# when the subscription is made and again at each delivery, and the connection goes to the address that was checked (so a name cannot change under us).
module Webhooks::UrlGuard
  class Refused < StandardError; end

  BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
              ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 ::ffff:0:0/96].map { |range| IPAddr.new(range) }.freeze

  def self.allow_http? = Rails.configuration.x.webhooks_allow_http == true
  def self.allow_private? = Rails.configuration.x.webhooks_allow_private == true

  def self.check_syntax(url)
    uri = URI.parse(url.to_s)
    raise Refused, "must be an https URL" unless uri.is_a?(URI::HTTPS) || (allow_http? && uri.is_a?(URI::HTTP))
    raise Refused, "must name a host" if uri.host.blank?
    raise Refused, "must not carry a user name or password" if uri.userinfo
    uri
  rescue URI::InvalidURIError
    raise Refused, "is not a valid URL"
  end

  # => [uri, ip]: the address to connect to, checked
  def self.resolve!(url)
    uri = check_syntax(url)
    addresses = IPAddr.new(uri.host).then { |ip| [ ip.to_s ] } rescue Resolv.getaddresses(uri.host)
    raise Refused, "the host #{uri.host} does not resolve" if addresses.empty?

    addresses.each { |address| raise Refused, "the host #{uri.host} is not a public address (#{address})" if !allow_private? && BLOCKED.any? { |range| range.include?(IPAddr.new(address)) } }
    [ uri, addresses.first ]
  end
end

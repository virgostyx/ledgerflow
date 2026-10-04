require "net/http"

# The one place that goes to the network for rates (F11), with timeouts; nothing else does, and no entry ever calls it (a scheduled job does).
module Rates::Http
  TIMEOUT = 15

  def self.get(url, source:)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.get(uri.request_uri) }
    yield response if block_given?
    raise Rates::Error, "#{source} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
    raise Rates::Error, "#{source} could not be reached (#{e.class.name.demodulize})"
  end
end

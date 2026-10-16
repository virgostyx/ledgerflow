class Rack::Attack
  # Throttle counters live in a memory store per process; in production the store is shared (Solid Cache), as the portal's limits must hold across processes.
  cache.store = Rails.env.production? ? Rails.cache : ActiveSupport::Cache::MemoryStore.new

  # Login throttle: 5 requests per 20 seconds per IP
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Passkey / recovery-code sign-in: same budget as password login
  throttle("passkey_logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.post? && %w[/passkey_session /recovery_code_session].include?(req.path)
  end

  # Guessing a two-factor code: 5 tries per 20 seconds per IP
  throttle("two_factor/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.post? && req.path.start_with?("/two_factor")
  end

  # The page where a third party answers a question (F08) is public: a link is tried, and a file uploaded, a few times a minute per IP
  throttle("external_reply/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/reply/")
  end

  # The public page of a certificate (B03c) is open to anyone who has the address: tried a few times a minute per IP
  throttle("verify/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/verify/")
  end

  # The client portal (B02a) is open to the world: five tries per 20 seconds per address, ten per hour per account whatever the addresses, and the same for codes and
  # invitation tokens. The lock after five failures (PortalUser) comes on top.
  portal = ->(req) { req.host == Rails.configuration.x.portal_host }

  throttle("portal_sign_in/ip", limit: 5, period: 20.seconds) { |req| req.ip if portal.(req) && req.post? && req.path == "/session" }

  throttle("portal_sign_in/account", limit: 10, period: 1.hour) do |req|
    Digest::SHA256.hexdigest(req.params["email"].to_s.strip.downcase) if portal.(req) && req.post? && req.path == "/session" && req.params["email"].present?
  end

  throttle("portal_codes/ip", limit: 5, period: 20.seconds) { |req| req.ip if portal.(req) && req.post? && req.path.start_with?("/second_factor") }

  throttle("portal_invitations/ip", limit: 20, period: 1.minute) { |req| req.ip if portal.(req) && req.path.start_with?("/invitations/") }

  # API throttle: 300 requests per minute per IP
  throttle("api/ip", limit: 300, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # ...and 300 per minute per API key, whatever the IPs it comes from (several applications may share one IP).
  # Keyed on a digest of the bearer token, so no secret ends up in the cache; not checked here, the app does that.
  throttle("api/key", limit: 300, period: 1.minute) do |req|
    token = req.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (.+)\z/, 1]
    Digest::SHA256.hexdigest(token)[0, 16] if req.path.start_with?("/api/") && token
  end

  # API clients get a JSON body and Retry-After (seconds until the window resets); the web keeps plain text.
  self.throttled_responder = lambda do |request|
    match = request.env["rack.attack.match_data"]
    if request.path.start_with?("/api/")
      retry_after = match[:period] - (match[:epoch_time] % match[:period])
      [ 429, { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
        [ { error: "Too Many Requests", retry_after: retry_after }.to_json ] ]
    else
      [ 429, { "Content-Type" => "text/plain" }, [ "Too Many Requests\n" ] ]
    end
  end
end

# Disabled in test — specs opt in via Rack::Attack.enabled = true
Rack::Attack.enabled = !Rails.env.test?

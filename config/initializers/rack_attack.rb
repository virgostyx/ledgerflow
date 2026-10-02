class Rack::Attack
  # Throttle counters live in a memory store per process.
  # In production swap to a shared store (e.g. Solid Cache) if needed.
  cache.store = ActiveSupport::Cache::MemoryStore.new

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

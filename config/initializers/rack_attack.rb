class Rack::Attack
  # Throttle counters live in a memory store per process.
  # In production swap to a shared store (e.g. Solid Cache) if needed.
  cache.store = ActiveSupport::Cache::MemoryStore.new

  # Login throttle: 5 requests per 20 seconds per IP
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # API throttle: 300 requests per minute per IP
  throttle("api/ip", limit: 300, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  self.throttled_responder = lambda do |_env|
    [ 429, { "Content-Type" => "text/plain" }, [ "Too Many Requests\n" ] ]
  end
end

# Disabled in test — specs opt in via Rack::Attack.enabled = true
Rack::Attack.enabled = !Rails.env.test?

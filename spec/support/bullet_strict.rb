# Opt-in N+1 enforcement for the reports module (docs/dev/reports/spec.md §2.4).
# Tag a spec with `bullet_strict: true` to fail it on any N+1 query. Bullet
# stays in log-only mode for the rest of the suite until the app's pre-existing
# N+1s (tracked in docs/dev/reports/QUESTIONS.md) are fixed one by one.
RSpec.configure do |config|
  config.around(:each, :bullet_strict) do |example|
    Bullet.raise = true
    example.run
  ensure
    Bullet.raise = false
  end
end

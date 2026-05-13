# Production-shaped settings used for local benchmarking. Mirrors
# config/settings/production.cr but:
#   - cookies aren't HTTPS-only (we hit the server over plain HTTP from k6)
#   - allowed_hosts / secret_key default to bench-friendly values
#
# Triggered via MARTEN_ENV=benchmark (binary must be built with --release for
# the comparison to be apples-to-apples vs Rails production).
Marten.configure :benchmark do |config|
  config.debug = false
  config.host = "127.0.0.1"
  config.port = 8000

  config.secret_key = ENV["MARTEN_SECRET_KEY"]? || "bench-insecure-key-do-not-deploy"

  config.allowed_hosts = (ENV["MARTEN_ALLOWED_HOSTS"]? || "127.0.0.1,localhost")
    .split(",")
    .map(&.strip)
    .reject(&.empty?)

  config.sessions.cookie_secure = false
  config.sessions.cookie_http_only = true

  config.csrf.cookie_secure = false
  config.csrf.cookie_http_only = false

  config.templates.cached = true
end

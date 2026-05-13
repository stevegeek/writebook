Marten.configure :production do |config|
  config.debug = false
  config.host = "0.0.0.0"
  config.port = 8000

  config.secret_key = ENV.fetch("MARTEN_SECRET_KEY")

  config.allowed_hosts = ENV.fetch("MARTEN_ALLOWED_HOSTS")
    .split(",")
    .map(&.strip)
    .reject(&.empty?)

  config.sessions.cookie_secure = true
  config.sessions.cookie_http_only = true

  config.csrf.cookie_secure = true
  config.csrf.cookie_http_only = true

  config.templates.cached = true

  # Serve collected assets directly from the app in production. Run
  # `script/manage collectassets` during deploy to populate `assets/`.
  config.middleware.unshift(Marten::Middleware::AssetServing)
end

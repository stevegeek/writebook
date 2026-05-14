Marten.configure do |config|
  # IMPORTANT: please ensure that the secret key value is kept secret!
  config.secret_key = "__insecure_writebook_dev_change_me_19f0b48f8b81461f9e3d7c34c1a0a7b1__"

  config.installed_apps = [
    MartenAuth::App,
    MartenImportmap::App,
    MartenStimulus::App,
    Accounts::App,
    Books::App,
    MartenTurbo::App,
  ] of Marten::Apps::Config.class

  # MartenAuth::Middleware reads the user-id from the session and attaches it
  # to the request as `request.user_id`. It MUST come after Session.
  config.middleware = [
    # ProfileLogMiddleware records total wall time + handler checkpoints
    # when PROFILE=1 is set. No-op (one branch) otherwise. Must be first
    # so the recorded total includes every other middleware's time.
    ProfileLogMiddleware,
    Marten::Middleware::Session,
    MartenAuth::Middleware,
    Marten::Middleware::Flash,
    Marten::Middleware::GZip,
    Marten::Middleware::XFrameOptions,
    Marten::Middleware::ReferrerPolicy,
  ]

  # marten-auth needs to know the User class. Set after models load — done
  # in an initializer (config/initializers/auth.cr) since this file runs
  # before model autoload.

  # Database — pick backend from DATABASE_URL if provided.
  # Accepts:
  #   postgres://user:pass@host:port/dbname
  #   sqlite:///path/to/file.db   (or unset → default sqlite file)
  config.database do |db| # ameba:disable Naming/BlockParameterName
    if (url = ENV["DATABASE_URL"]?) && !url.empty?
      uri = URI.parse(url)
      case uri.scheme
      when "postgres", "postgresql"
        db.backend = :postgresql
        db.host = uri.host
        db.port = uri.port
        db.user = uri.user
        db.password = uri.password
        db.name = uri.path.lchop('/')
        # PG over tailscale will reap idle connections. Retry past stale
        # sockets, and pre-warm a full pool to avoid the ~1s TCP+TLS
        # handshake whenever crystal-db has to grow the pool under load.
        #
        # ProfileLog data from a 30-VU bench showed the heavy-tail
        # outliers (~1100ms) coincided with `pool_wait_max ≈ 1000ms` on
        # a single db.open call — that's the cost of establishing a
        # fresh connection over the tailscale hop. Pre-creating every
        # connection at boot kills that spike; raising max_pool_size
        # well above the steady-state in-flight query count (~6 per
        # request × 30 concurrent VUs / 16 slots ≈ 11x oversubscription
        # before the change) kills the ~200ms steady-state queue tail.
        db.retry_attempts = 3
        db.initial_pool_size = 16
        db.max_idle_pool_size = 16
        db.max_pool_size = 32
      when "sqlite", "sqlite3"
        db.backend = :sqlite
        db.name = uri.path.lchop('/').empty? ? Path["marten_writebook.db"].expand.to_s : uri.path.lchop('/')
      else
        raise "Unsupported DATABASE_URL scheme: #{uri.scheme}"
      end
    else
      db.backend = :sqlite
      db.name = Path["marten_writebook.db"].expand
    end
  end

  config.templates.context_producers = [
    Marten::Template::ContextProducer::Request,
    Marten::Template::ContextProducer::Flash,
    Marten::Template::ContextProducer::Debug,
    Marten::Template::ContextProducer::I18n,
    Accounts::AuthContextProducer,
  ]

  config.templates.dirs = [
    Path["src/templates"].expand.to_s,
  ]

  config.assets.dirs = [
    Path["src/assets"].expand.to_s,
  ]

  # i18n — Writebook supports 6 locales for the field-label translation
  # popovers. Locale YAMLs live in config/locales/.
  config.i18n.default_locale = :en
  config.i18n.available_locales = [:en, :es, :fr, :hi, :de, :pt]
end

Marten.configure do |config|
  # IMPORTANT: please ensure that the secret key value is kept secret!
  config.secret_key = "__insecure_writebook_dev_change_me_19f0b48f8b81461f9e3d7c34c1a0a7b1__"

  config.installed_apps = [
    MartenAuth::App,
    Accounts::App,
    Books::App,
    MartenTurbo::App,
  ] of Marten::Apps::Config.class

  # MartenAuth::Middleware reads the user-id from the session and attaches it
  # to the request as `request.user_id`. It MUST come after Session.
  config.middleware = [
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

  config.database do |db| # ameba:disable Naming/BlockParameterName
    db.backend = :sqlite
    db.name = Path["marten_writebook.db"].expand
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

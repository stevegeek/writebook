Marten.configure :test do |config|
  config.database do |db| # ameba:disable Naming/BlockParameterName
    db.name = ":memory:"
  end

  config.allowed_hosts = ["127.0.0.1"]
  config.cache_store = Marten::Cache::Store::Null.new

  config.emailing.backend = Marten::Emailing::Backend::Development.new(collect_emails: true, print_emails: false)
end

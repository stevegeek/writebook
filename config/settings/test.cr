Marten.configure :test do |config|
  config.database do |db| # ameba:disable Naming/BlockParameterName
    # Why not `:memory:`? SQLite gives each connection that opens `:memory:`
    # its own private database, so the pool's nth connection has no schema.
    # Handler tests in particular hit this: Searchable.search opens an inner
    # connection while the outer request is mid-flight, races to a second
    # pool slot, and finds an empty db. A temp file is shared across the
    # whole pool and torn down at process exit, giving us the right semantics.
    #
    # System (browser) specs additionally need a stable path so the spawned
    # `bin/server` subprocess loads the same DB as the spec process. Honor
    # MARTEN_TEST_DB if set; fall back to a fresh tempfile per process.
    db.name = ENV["MARTEN_TEST_DB"]? || File.tempfile("marten-writebook-test-", ".db").path
  end

  config.allowed_hosts = ["127.0.0.1"]
  config.cache_store = Marten::Cache::Store::Null.new

  # Host/port — only consulted when a real listener is started (system specs).
  # Handler specs go through Marten::Spec::Client and never bind a socket, so
  # these are inert for them.
  config.host = "127.0.0.1"
  config.port = (ENV["MARTEN_TEST_PORT"]? || "8765").to_i

  config.emailing.backend = Marten::Emailing::Backend::Development.new(collect_emails: true, print_emails: false)
end

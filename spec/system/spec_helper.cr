# System-spec entry point — drives headless Chrome against a real bin/server
# subprocess. Separate from spec/spec_helper.cr because:
#
#   - we set MARTEN_TEST_DB + MARTEN_TEST_PORT *before* requiring marten so
#     both this spec process AND the spawned bin/server pick up the same
#     SQLite file and the chosen port.
#   - the spawned server is a separate process; it loads the same
#     `Marten.configure :test` block via MARTEN_ENV=test and reads our env
#     vars to wire the shared DB / port.
#   - LuckyFlow + Selenium take a while to spin up; not worth paying for
#     handler-only spec runs.

ENV["MARTEN_ENV"] = "test"

# Stable per-run paths the server subprocess will share.
ENV["MARTEN_TEST_DB"] ||= File.tempfile("marten-writebook-system-", ".db").path

# Pick a port unless caller already chose one. We can't trivially grab a
# truly-free port across two processes, so default to 8765 and let the user
# override via MARTEN_TEST_PORT=NNNN if it collides.
ENV["MARTEN_TEST_PORT"] ||= "8765"

require "spec"
require "lucky_flow"
require "../../src/project"
require "marten/spec"

require "../support/factories"
require "../support/sessions"
require "./support/**"

LuckyFlow.configure do |settings| # ameba:disable Naming/BlockParameterName
  settings.base_uri = "http://127.0.0.1:#{ENV["MARTEN_TEST_PORT"]}"
end
Habitat.raise_if_missing_settings!

LuckyFlow::Spec.setup

# Build + spawn the server subprocess once for the suite. Each spec gets a
# fresh DB schema (flushed by Marten::Spec.after_each); the server keeps
# running across the suite.
module SystemSpec::ServerProcess
  @@process : ::Process? = nil
  @@log_path : String = "/tmp/marten-writebook-system-server.log"

  def self.start : Nil
    binary = File.expand_path("./bin/server")
    unless File.exists?(binary)
      raise "bin/server is missing — run `script/serve` once to build, then re-run system specs"
    end

    log = File.open(@@log_path, "w")
    @@process = ::Process.new(
      binary,
      env: {
        "MARTEN_ENV"       => "test",
        "MARTEN_TEST_DB"   => ENV["MARTEN_TEST_DB"],
        "MARTEN_TEST_PORT" => ENV["MARTEN_TEST_PORT"],
      },
      output: log,
      error: log,
    )

    # Block until the server is accepting connections (or fail loudly).
    LuckyFlow.wait_for_server(timeout: 10.seconds)
  end

  def self.stop : Nil
    if (p = @@process)
      p.signal(::Signal::TERM) rescue nil
      p.wait rescue nil
    end
    @@process = nil
  end
end

Spec.before_suite do
  # FTS5 virtual table — Marten::Spec.setup_databases uses sync_models which
  # doesn't run hand-written SQL migrations. Mirror what production migrations
  # would produce.
  Marten::DB::Connection.default.open do |db|
    db.exec("DROP TABLE IF EXISTS leaf_search_index")
    db.exec(
      "CREATE VIRTUAL TABLE leaf_search_index USING fts5(" \
      "title, content, tokenize='porter unicode61 remove_diacritics 2')"
    )
  end
  SystemSpec::ServerProcess.start
end

Spec.after_suite do
  SystemSpec::ServerProcess.stop
end

# flush_databases doesn't know about the FTS5 virtual table; wipe it ourselves
# so rows from previous specs don't bleed through. flush_databases itself is
# auto-registered by `require "marten/spec"`.
Spec.after_each do
  Marten::DB::Connection.default.open do |db|
    db.exec("DELETE FROM leaf_search_index")
  end
end

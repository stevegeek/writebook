# Lightweight per-request tracing for the writebook app. Gated on the
# PROFILE=1 environment variable so it costs nothing when unset (the
# `enabled?` flag is read once at boot for the macro inline check; each
# checkpoint also short-circuits if disabled).
#
# Usage from a handler:
#
#   ProfileLog.checkpoint("leaves_load") do
#     book.leaves.active.with_leafables.order(...).to_a
#   end
#
# The middleware (config/initializers/profile_log.cr wires it into the
# stack) calls `ProfileLog.start` on request entry and `ProfileLog.finish`
# on exit; finish emits one log line per request containing the total
# wall time plus every recorded checkpoint:
#
#   req path=/books/1 method=GET status=200 total=87.45ms \
#     ensure_accessable=2.13ms leaves_load=28.97ms preload_bodies=14.21ms \
#     cover=9.07ms render=24.85ms
#
# The trace is held in a class-level Hash keyed by `Fiber.current.object_id`
# so concurrent requests on different fibers don't clobber each other. The
# Crystal HTTP server uses one fiber per request which is what we want.
module ProfileLog
  alias Checkpoint = NamedTuple(label: String, ms: Float64)

  # Cached at boot so the hot path is a constant load instead of an ENV
  # lookup per checkpoint. Toggling PROFILE requires a server restart —
  # acceptable for an introspection tool.
  ENABLED = ENV["PROFILE"]? == "1"

  @@traces = {} of UInt64 => Array(Checkpoint)

  # Per-fiber tally of `Marten::DB::Connection::Base#open` calls, fed
  # by `profile_log_pool_patch.cr`. Tracks total + max pool-wait + total
  # query-exec, separated so a slow request can be classified as
  # pool-saturation vs slow-query vs render-bound at a glance.
  record PoolTally,
    calls : Int32 = 0,
    wait_total_ms : Float64 = 0.0,
    wait_max_ms : Float64 = 0.0,
    exec_total_ms : Float64 = 0.0

  @@pool_tallies = {} of UInt64 => PoolTally

  def self.enabled? : Bool
    ENABLED
  end

  # Called by the middleware at request entry.
  def self.start : Nil
    return unless ENABLED
    fiber_id = Fiber.current.object_id
    @@traces[fiber_id] = [] of Checkpoint
    @@pool_tallies[fiber_id] = PoolTally.new
  end

  # Record the wall time of a code block under `label`. Returns whatever
  # the block returns; no-op (just yields) when PROFILE is unset.
  def self.checkpoint(label : String, &)
    return yield unless ENABLED
    started = Time.monotonic
    begin
      result = yield
    ensure
      ms = (Time.monotonic - started).total_milliseconds
      trace = @@traces[Fiber.current.object_id]?
      trace << {label: label, ms: ms} if trace
    end
    result
  end

  # Called from the connection-open patch (profile_log_pool_patch.cr) for
  # each db connection acquired during a request. wait_ms is the time
  # spent waiting for a pool slot; exec_ms is the time the SQL block ran.
  def self.record_pool_call(wait_ms : Float64, exec_ms : Float64) : Nil
    return unless ENABLED
    fiber_id = Fiber.current.object_id
    tally = @@pool_tallies[fiber_id]?
    return if tally.nil?
    @@pool_tallies[fiber_id] = PoolTally.new(
      calls: tally.calls + 1,
      wait_total_ms: tally.wait_total_ms + wait_ms,
      wait_max_ms: wait_ms > tally.wait_max_ms ? wait_ms : tally.wait_max_ms,
      exec_total_ms: tally.exec_total_ms + exec_ms,
    )
  end

  # Called by the middleware at request exit. Logs one summary line and
  # discards the per-fiber trace. Safe to call when no trace was started.
  def self.finish(request : Marten::HTTP::Request, status : Int32, total_ms : Float64) : Nil
    return unless ENABLED
    fiber_id = Fiber.current.object_id
    checkpoints = @@traces.delete(fiber_id)
    tally = @@pool_tallies.delete(fiber_id)
    breakdown = checkpoints ? checkpoints.map { |c| "#{c[:label]}=#{c[:ms].round(2)}ms" }.join(" ") : ""
    pool = tally ? (
      "db_calls=#{tally.calls} " \
      "pool_wait_total=#{tally.wait_total_ms.round(2)}ms " \
      "pool_wait_max=#{tally.wait_max_ms.round(2)}ms " \
      "query_exec_total=#{tally.exec_total_ms.round(2)}ms"
    ) : ""
    Log.info {
      "req path=#{request.path} method=#{request.method} status=#{status} " \
      "total=#{total_ms.round(2)}ms #{breakdown} #{pool}".strip.gsub(/ +/, " ")
    }
  end
end

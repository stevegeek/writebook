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

  def self.enabled? : Bool
    ENABLED
  end

  # Called by the middleware at request entry.
  def self.start : Nil
    return unless ENABLED
    @@traces[Fiber.current.object_id] = [] of Checkpoint
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

  # Called by the middleware at request exit. Logs one summary line and
  # discards the per-fiber trace. Safe to call when no trace was started.
  def self.finish(request : Marten::HTTP::Request, status : Int32, total_ms : Float64) : Nil
    return unless ENABLED
    checkpoints = @@traces.delete(Fiber.current.object_id)
    breakdown = checkpoints ? checkpoints.map { |c| "#{c[:label]}=#{c[:ms].round(2)}ms" }.join(" ") : ""
    Log.info {
      "req path=#{request.path} method=#{request.method} status=#{status} " \
      "total=#{total_ms.round(2)}ms #{breakdown}".strip
    }
  end
end

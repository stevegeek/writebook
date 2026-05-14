# Wraps every request to drive the ProfileLog tracer (see profile_log.cr).
# Insert at the very front of the middleware stack so the recorded total
# includes the time spent in every inner middleware (sessions, auth, etc.).
#
# When PROFILE is unset this is a near-zero-cost passthrough: one
# branch + a Time.monotonic read isn't worth gating away.
class ProfileLogMiddleware < Marten::Middleware
  def call(request : Marten::HTTP::Request, get_response : Proc(Marten::HTTP::Response)) : Marten::HTTP::Response
    return get_response.call unless ProfileLog.enabled?

    ProfileLog.start
    started = Time.monotonic
    response : Marten::HTTP::Response? = nil
    begin
      response = get_response.call
      response
    ensure
      total_ms = (Time.monotonic - started).total_milliseconds
      status = response.try(&.status.to_i32) || 0
      ProfileLog.finish(request, status, total_ms)
    end
  end
end

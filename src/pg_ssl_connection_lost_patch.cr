# crystal-pg (as of 0.29.0) only rescues `IO::Error` and re-raises as
# `DB::ConnectionLost` so the pool can retry on a dead socket. When the
# connection is TLS-wrapped (typical for a remote postgres), a half-closed
# socket surfaces as `OpenSSL::SSL::Error` ("SSL_write: Unexpected EOF
# while reading"), which is NOT an IO::Error — it inherits from
# OpenSSL::Error -> Exception. The exception bubbles all the way out and
# the request 500s instead of being retried on a fresh connection.
#
# Override the two crystal-pg entrypoints to also rescue that error class.
require "openssl"

class PG::Statement < ::DB::Statement
  protected def perform_query(args : Enumerable) : ResultSet
    params = args.map { |arg| PQ::Param.encode(arg) }
    conn = self.conn
    conn.send_parse_message(command)
    conn.send_bind_message params
    conn.send_describe_portal_message
    conn.send_execute_message
    conn.send_sync_message
    conn.expect_frame PQ::Frame::ParseComplete
    conn.expect_frame PQ::Frame::BindComplete
    frame = conn.read
    case frame
    when PQ::Frame::RowDescription
      fields = frame.fields
    when PQ::Frame::NoData
      fields = nil
    else
      raise "expected RowDescription or NoData, got #{frame}"
    end
    ResultSet.new(self, fields)
  rescue e : IO::Error | OpenSSL::SSL::Error
    raise DB::ConnectionLost.new(connection, cause: e)
  end

  protected def perform_exec(args : Enumerable) : ::DB::ExecResult
    result = perform_query(args)
    result.each { }
    ::DB::ExecResult.new(
      rows_affected: result.rows_affected,
      last_insert_id: 0_i64 # postgres doesn't support this
    )
  rescue e : IO::Error | OpenSSL::SSL::Error
    raise DB::ConnectionLost.new(connection, cause: e)
  end
end

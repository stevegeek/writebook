module Books
  # Handler-level helpers for pulling typed values out of request params
  # / model PKs. Used by handlers that accept multi-value ID lists from
  # form posts (editor_ids[], reader_ids[]) and need to normalize raw
  # Int32/Int64 PK values into Int64 for set membership.
  #
  # Usage:
  #
  #   class FooHandler < Marten::Handler
  #     include Books::RequestParams
  #
  #     def post
  #       ids = collect_ids("editor_ids")
  #       uid = pk_to_i64(current_user.try(&.id))
  #       ...
  #     end
  #   end
  module RequestParams
    # Parse a multi-value param submitted as repeated keys
    # (e.g. `editor_ids=1&editor_ids=2`) and return an array of Int64 IDs.
    # Empty strings and unparseable values are silently dropped.
    protected def collect_ids(param_name : String) : Array(Int64)
      values = request.data.fetch_all(param_name, nil)
      return [] of Int64 if values.nil?
      values.compact_map do |v|
        str = v.to_s
        next nil if str.empty?
        Int64.new(str) rescue nil
      end
    end

    # Normalise a model PK (which Marten exposes as Int32 | Int64 | other
    # depending on schema) to Int64. Returns nil for anything that isn't
    # an integer (including nil itself).
    protected def pk_to_i64(value) : Int64?
      case value
      when Int32 then value.to_i64
      when Int64 then value
      else            nil
      end
    end
  end
end

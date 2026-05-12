module ApplicationCable
  class Connection < Cable::Connection
    # Writebook authenticates per-request via the session cookie. Cable's
    # default identifier flow runs before our session middleware, so we
    # capture the raw HTTP::Request here and resolve the user from the
    # session cookie via MartenCable::Session.
    #
    # For now we accept anonymous connections (Writebook has public-readable
    # books). `connect` is the place to install reject_unauthorized_connection
    # for streams that need a signed-in user.
    identified_by :user_identifier

    def connect
      self.user_identifier = "anon"
    end
  end
end

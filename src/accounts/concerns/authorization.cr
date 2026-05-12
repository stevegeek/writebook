module Accounts
  # Authorization helpers — mirrors Rails' `app/models/concerns/authorization.rb`.
  #
  # Kept separate from `AuthenticationHelpers` for the same reason Rails
  # splits authentication and authorization concerns: authn answers "who is
  # this?", authz answers "are they allowed?". Wire up alongside
  # AuthenticationHelpers (which provides `current_user`):
  #
  #   class FooHandler < Marten::Handler
  #     include Accounts::AuthenticationHelpers
  #     include Accounts::Authorization
  #     before_dispatch :require_authentication
  #     before_dispatch :ensure_can_administer
  #   end
  #
  # `ensure_current_user` (the Rails second method) is not provided here
  # because the Marten port's profiles handler resolves its target inline
  # rather than via a `set_user` before_action — when a second handler
  # needs the same "me or admin" check it can move into this module.
  module Authorization
    # Returns 403 unless the signed-in user is an administrator.
    # Use as a `before_dispatch` callback on admin-only handlers.
    protected def ensure_can_administer : Marten::HTTP::Response?
      return nil if current_user.try(&.administrator?)
      head(:forbidden)
    end
  end
end

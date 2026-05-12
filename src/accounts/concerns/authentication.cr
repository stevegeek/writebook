module Accounts
  # Handler helpers wrapping marten-auth's request-level API.
  #
  # - `request.user`     → MartenAuth::BaseUser? (set by MartenAuth::Middleware
  #                        on every request, sourced from the session)
  # - `request.user!`    → BaseUser (raises if anonymous)
  # - `request.user?`    → Bool
  # - `MartenAuth.sign_in(request, user)`  signs the user in (sets the session key)
  # - `MartenAuth.sign_out(request)`       clears the session
  # - `MartenAuth.authenticate(email, pwd) → BaseUser?` validates credentials
  #
  # Handlers that need to enforce sign-in just declare:
  #
  #   class FooHandler < Marten::Handler
  #     include Accounts::AuthenticationHelpers
  #     before_dispatch :require_authentication
  #   end
  module AuthenticationHelpers
    protected def signed_in? : Bool
      !request.user.nil?
    end

    protected def current_user : User?
      request.user.try(&.as(User))
    end

    protected def current_user! : User
      request.user!.as(User)
    end

    # Mirrors Rails' `user.current?` — true if the given user is the
    # signed-in user. Wraps User#current? so handlers don't have to repeat
    # the `current_user` lookup at every callsite.
    protected def current?(user : User?) : Bool
      user.try(&.current?(current_user)) || false
    end

    protected def require_authentication : Marten::HTTP::Response?
      return nil if signed_in?
      # Save the original URL so SessionsCreateHandler#post_authenticating_url
      # can return the user there after a successful sign-in (matches Rails
      # Authentication#request_authentication).
      if request.method == "GET"
        request.session["return_to_after_authenticating"] = request.full_path.to_s
      end
      redirect(Marten.routes.reverse("accounts:session_new"))
    end
  end
end

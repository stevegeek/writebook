module Accounts
  # Sign in / sign out via marten-auth. Mirrors Rails' SessionsController.

  class SessionsNewHandler < Marten::Handler
    before_dispatch :ensure_user_exists

    def get
      render("sessions/new.html", context: {errors: nil, email_address: ""})
    end

    # Mirrors Rails' `before_action :ensure_user_exists, only: :new` — diverts
    # to the first-run setup flow when there are no users yet.
    private def ensure_user_exists : Marten::HTTP::Response?
      return nil if User.all.exists?
      redirect(Marten.routes.reverse("accounts:first_run_new"))
    end
  end

  class SessionsCreateHandler < Marten::Handlers::Schema
    schema SessionSchema
    template_name "sessions/new.html"

    def process_valid_schema
      email = schema.validated_data["email_address"].as(String)
      password = schema.validated_data["password"].as(String)

      user = MartenAuth.authenticate(email, password)
      return render_rejection(422, email) if user.nil? || !user.as(User).active

      MartenAuth.sign_in(request, user)
      redirect(post_authenticating_url)
    end

    # Mirrors Rails' SessionsController#render_rejection — re-renders the
    # sign-in form with an error message and the (preserved) email field.
    # Rails uses `:unauthorized` (401) for credential failure; we keep
    # 422 to match the rest of the Marten form error responses and the
    # existing spec expectations.
    private def render_rejection(status : Int32, email_address : String)
      render(
        "sessions/new.html",
        context: {errors: ["Invalid email or password"], email_address: email_address},
        status: status,
      )
    end

    # Mirrors Rails' Authentication#post_authenticating_url: pop the saved
    # `return_to_after_authenticating` URL out of the session and redirect
    # there, falling back to the books index ("root").
    private def post_authenticating_url : String
      target = request.session.delete("return_to_after_authenticating")
      target.try(&.to_s).presence || Marten.routes.reverse("books:index")
    end
  end

  class SessionsDeleteHandler < Marten::Handler
    include AuthenticationHelpers

    def post
      MartenAuth.sign_out(request)
      redirect(Marten.routes.reverse("accounts:session_new"))
    end
  end
end

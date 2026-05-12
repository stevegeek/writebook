module Accounts
  # Sign in / sign out via marten-auth.
  class SessionsNewHandler < Marten::Handler
    def get
      # Mirrors Rails' SessionsController#ensure_user_exists — if there are
      # no users yet, divert to the first-run setup flow.
      return redirect(Marten.routes.reverse("accounts:first_run_new")) unless User.all.exists?
      render("sessions/new.html", context: {errors: nil, email_address: ""})
    end
  end

  class SessionsCreateHandler < Marten::Handlers::Schema
    schema SessionSchema
    template_name "sessions/new.html"

    def process_valid_schema
      email = schema.validated_data["email_address"].as(String)
      password = schema.validated_data["password"].as(String)

      user = MartenAuth.authenticate(email, password)
      if user.nil? || !user.as(User).active
        return render(
          "sessions/new.html",
          context: {errors: ["Invalid email or password"], email_address: email},
          status: 422,
        )
      end

      MartenAuth.sign_in(request, user)
      redirect(post_authenticating_url)
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

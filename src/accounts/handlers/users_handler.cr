module Accounts
  # GET /users — signed-in-visible list of active users + join-code share link.
  # Per-row role-toggle / delete controls are disabled in `_user.html` for
  # non-admins. Matches Rails, which lets any signed-in user view the people
  # list (just with read-only controls). The cog icon on the library page
  # links here for everyone, so admin-gating here was wrong.
  class UsersIndexHandler < Marten::Handlers::RecordList
    include AuthenticationHelpers

    model User
    template_name "users/index.html"
    list_context_name "users"

    before_dispatch :require_authentication
    before_render :inject_account

    def queryset
      super.filter(active: true).order(:name)
    end

    private def require_admin : Marten::HTTP::Response?
      return nil if current_user.try(&.administrator?)
      redirect(Marten.routes.reverse("books:index"))
    end

    private def inject_account : Nil
      account = Account.first!
      context[:account] = account
      join_path = Marten.routes.reverse("accounts:users_new", join_code: account.join_code)
      base_url = "#{request.scheme}://#{request.host}"
      context[:join_url] = base_url + join_path
    end
  end

  # POST /users/<id>/update — admin-only role toggle.
  class UsersUpdateHandler < Marten::Handlers::Schema
    include AuthenticationHelpers

    schema UserRoleSchema
    template_name "users/index.html"

    before_dispatch :require_authentication
    before_dispatch :require_admin

    def process_valid_schema
      me = current_user!
      target = User.filter(active: true).get(id: params["id"])
      return head(:not_found) if target.nil?

      # Server-side guard mirroring the disabled-on-self UI control: an
      # admin can't demote (or, redundantly, promote) themselves, otherwise
      # the last admin could lock themselves out of /users.
      return head(:forbidden) if target.id == me.id

      raw_role = schema.validated_data["role"]?.try(&.as(String)) || ""
      new_role = %w[administrator].includes?(raw_role) ? raw_role : "member"

      target.update!(role: new_role)
      redirect(Marten.routes.reverse("accounts:users_index"))
    end
  end

  # POST /users/<id>/delete — admin-only deactivate (sets active=false, scrambles email).
  class UsersDeleteHandler < Marten::Handler
    include AuthenticationHelpers

    before_dispatch :require_authentication
    before_dispatch :require_admin

    def post
      me = current_user!
      target = User.filter(active: true).get(id: params["id"])
      return head(:not_found) if target.nil?

      # Cannot delete yourself.
      return head(:forbidden) if target.id == me.id

      target.deactivate
      redirect(Marten.routes.reverse("accounts:users_index"))
    end
  end

  # POST /account/join_codes — admin-only; regenerates the join code.
  class JoinCodesCreateHandler < Marten::Handler
    include AuthenticationHelpers

    before_dispatch :require_authentication
    before_dispatch :require_admin

    def post
      Account.first!.reset_join_code!
      redirect(Marten.routes.reverse("accounts:users_index"))
    end
  end

  # GET /join/<code>  — public sign-up form (unauthed; validates join code).
  # POST /join/<code> — create user, sign in, redirect to root.
  class UsersNewHandler < Marten::Handlers::Schema
    schema UserSchema
    template_name "users/new.html"

    before_dispatch :verify_join_code
    before_render :inject_join_code

    def process_valid_schema
      # Double-check the code (belt-and-suspenders; before_dispatch already ran).
      return head(:not_found) unless join_code_valid?

      name          = schema.validated_data["name"].as(String).strip
      email         = schema.validated_data["email_address"].as(String).strip
      password      = schema.validated_data["password"].as(String)

      user = User.new(name: name, email: email, role: "member", active: true)
      user.set_password(password)
      user.save!

      MartenAuth.sign_in(request, user)
      redirect("/")
    rescue e : Marten::DB::Errors::InvalidRecord
      return render(
        "users/new.html",
        context: {schema: schema, errors: [e.message || "Could not create account. The email may already be in use."]},
        status: 422,
      )
    rescue e : DB::Error
      return render(
        "users/new.html",
        context: {schema: schema, errors: ["An account with that email already exists."]},
        status: 422,
      )
    end

    private def inject_join_code : Nil
      context[:join_code] = params["join_code"]? || ""
    end

    private def verify_join_code : Marten::HTTP::Response?
      return nil if join_code_valid?
      head(:not_found)
    end

    private def join_code_valid? : Bool
      code = params["join_code"]?
      return false if code.nil?
      account = Account.all.first?
      return false if account.nil?
      account.join_code == code
    end
  end
end

module Accounts
  # GET /profile          — profile show page for the signed-in user (self).
  # GET /users/<id>/profile — admin can view any user; non-admin only self (403).
  #
  # Mirrors Rails' Users::ProfilesController#show, which is nested under
  # `resources :users do resource :profile end` (= `/users/<id>/profile`).
  # Rails uses `UserScoped` to look up `@user` from `params[:user_id]`; we
  # accept an optional `id` route param and fall back to `current_user`
  # (so the legacy `/profile` shortcut still works for the navbar avatar
  # link). The admin-only Transfer block follows the same admin gate so
  # an administrator viewing their own profile still sees the "share
  # auto-login link" UI just like Rails.
  class ProfilesShowHandler < Marten::Handler
    include AuthenticationHelpers
    include UrlHelpers

    before_dispatch :require_authentication

    def get
      me = current_user!
      target = resolve_target_user(me)
      return head(:not_found) if target.nil?
      return head(:forbidden) unless authorized?(me, target)

      token = TransferToken.generate(target)
      transfer_url = absolute_url("accounts:transfers_show", token: token)
      self_view = target.id == me.id
      render(
        "profiles/show.html",
        context: {
          user:           target,
          transfer_url:   transfer_url,
          self_view:      self_view,
          # When an admin views another user's profile, the Transfer partial
          # uses different labels ("Share to get them back into their account"
          # vs. "Link to automatically log in on another device").
          transfer_other: !self_view,
        }
      )
    end

    # Returns the user the request is targeting:
    # - If `id` is present in the route, look up that user (active only).
    # - Otherwise, fall back to the signed-in user (legacy `/profile` route).
    private def resolve_target_user(me : User) : User?
      raw_id = params["id"]?
      return me if raw_id.nil?
      return me if raw_id.to_s == me.id.to_s
      User.active_get(raw_id)
    end

    private def authorized?(me : User, target : User) : Bool
      me.id == target.id || me.administrator?
    end
  end

  # GET  /profile/edit                 — edit form for the current user (self).
  # POST /profile/edit                 — save updates for the current user.
  # GET  /users/<id>/profile/edit      — admin can edit any user; else 403.
  # POST /users/<id>/profile/edit      — same auth rules as GET.
  #
  # Mirrors Rails' Users::ProfilesController#edit/update. Rails' controller
  # uses `before_action :ensure_current_user, only: %i[edit update]`, but
  # `ensure_current_user` allows admins to act on any user (it's the
  # "current_user OR can_administer?" check). After save, Rails redirects
  # to `users_url` (the People page) — we mirror that here.
  class ProfilesEditHandler < Marten::Handlers::Schema
    include AuthenticationHelpers
    include UrlHelpers

    schema ProfileSchema
    template_name "profiles/edit.html"

    before_dispatch :require_authentication
    before_dispatch :require_authorized_target
    before_render :inject_user
    before_render :inject_transfer_url
    before_render :inject_form_action

    # Pre-populate the form from the target user on GET (and on POST when
    # invalid, so the user's existing name/email come back rather than
    # blanks). Falls back to the signed-in user if no `id` param is given.
    def initial_data
      user = target_user
      Marten::Schema::DataHash{
        "name"          => user.name,
        "email_address" => user.email || "",
      }
    end

    def process_valid_schema
      user = target_user

      name = schema.validated_data["name"].as(String).strip
      email = schema.validated_data["email_address"].as(String).strip
      password = schema.validated_data["password"]?.try(&.as(String))

      user.name = name
      user.email = email

      unless password.nil? || password.empty?
        user.set_password(password)
      end

      user.save!
      redirect(Marten.routes.reverse("accounts:users_index"))
    end

    # Memoised lookup: route's `id` if present (admin-or-self only),
    # otherwise the signed-in user. The `require_authorized_target`
    # before_dispatch callback ensures non-admins cannot target other users.
    @target_user : User? = nil

    private def target_user : User
      cached = @target_user
      return cached if cached
      me = current_user!
      raw_id = params["id"]?
      resolved =
        if raw_id.nil? || raw_id.to_s == me.id.to_s
          me
        else
          User.active_get!(raw_id)
        end
      @target_user = resolved
      resolved
    end

    private def require_authorized_target : Marten::HTTP::Response?
      me = current_user!
      raw_id = params["id"]?
      return nil if raw_id.nil? # no id ⇒ editing self
      return nil if raw_id.to_s == me.id.to_s
      # Cross-user edit only allowed for admins.
      return head(:forbidden) unless me.administrator?
      # Confirm the target exists; 404 if not.
      target = User.active_get(raw_id)
      return head(:not_found) if target.nil?
      nil
    end

    private def inject_user : Nil
      context[:user] = target_user
    end

    private def inject_transfer_url : Nil
      user = target_user
      token = TransferToken.generate(user)
      context[:transfer_url] = absolute_url("accounts:transfers_show", token: token)
      self_view = target_user.id == current_user!.id
      context[:self_view] = self_view
      context[:transfer_other] = !self_view
    end

    # The form posts back to the same URL that rendered the GET so that
    # admins editing another user stay on `/users/<id>/profile/edit`
    # rather than accidentally posting to `/profile/edit` (which would
    # silently edit themselves).
    private def inject_form_action : Nil
      me = current_user!
      target = target_user
      context[:form_action] =
        if target.id == me.id && params["id"]?.nil?
          Marten.routes.reverse("accounts:profile_edit")
        else
          Marten.routes.reverse("accounts:profile_edit_user", id: target.id)
        end
    end
  end
end

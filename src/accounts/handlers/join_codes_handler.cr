module Accounts
  # POST /account/join_codes — admin-only; regenerates the join code.
  # Mirrors Rails' `app/controllers/accounts/join_codes_controller.rb`.
  class JoinCodesCreateHandler < Marten::Handler
    include AuthenticationHelpers
    include Authorization

    before_dispatch :require_authentication
    before_dispatch :ensure_can_administer

    def post
      Account.first!.reset_join_code!
      redirect(Marten.routes.reverse("accounts:users_index"))
    end
  end
end

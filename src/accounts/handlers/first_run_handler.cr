module Accounts
  # Bootstrap the singleton Account + first administrator user via marten-auth.
  # Mirrors Rails `FirstRun.create!` / `FirstRunsController#create`:
  #   - Account name is hard-coded to "Writebook" (Rails: FirstRun::ACCOUNT_NAME).
  #   - On success, seed the Writebook Manual demo book (Rails:
  #     `DemoContent.create_manual(user)`).
  class FirstRunNewHandler < Marten::Handler
    def get
      # Once an Account exists, /first_run is gone — mirrors Rails'
      # before_action :prevent_running_after_setup which redirects to root.
      return redirect("/") if Account.all.exists?
      render("first_run/new.html", context: {errors: nil})
    end
  end

  class FirstRunCreateHandler < Marten::Handlers::Schema
    # Account name used when bootstrapping via /first_run. Mirrors Rails'
    # FirstRun::ACCOUNT_NAME.
    ACCOUNT_NAME = "Writebook"

    schema FirstRunSchema
    template_name "first_run/new.html"

    def process_valid_schema
      return redirect("/") if Account.all.exists?

      name = schema.validated_data["name"].as(String).strip
      email = schema.validated_data["email_address"].as(String).strip
      password = schema.validated_data["password"].as(String)

      user = nil
      Marten::DB::Connection.default.transaction do
        Account.create_with_defaults!(ACCOUNT_NAME)

        user = User.new(name: name, email: email, role: "administrator", active: true)
        user.set_password(password)
        user.save!
      end

      # Seed the Writebook Manual demo book for the new admin (mirrors
      # Rails' DemoContent.create_manual(user) inside FirstRun.create!).
      # The seeder logs to STDOUT; we don't fail the request if it errors.
      seed_demo_manual

      MartenAuth.sign_in(request, user.not_nil!)
      redirect(Marten.routes.reverse("books:index"))
    end

    private def seed_demo_manual : Nil
      # Reuse the existing CLI seeder. It's idempotent and silently skips
      # when the book already exists. Quiet its STDOUT logging — we're inside
      # a web request, not a terminal session.
      sink = IO::Memory.new
      command = ::Books::SeedManualCommand.new(options: [] of String, stdout: sink, stderr: sink)
      command.handle
    rescue ex
      Log.warn { "first_run: seed_demo_manual failed: #{ex.message}" }
    end
  end
end

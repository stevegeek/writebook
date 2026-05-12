require "../../spec_helper"

describe "Accounts session handlers" do
  describe "GET /session/new" do
    it "renders the sign-in form when at least one user exists" do
      Spec::Factories.create_account
      Spec::Factories.create_user

      response = Marten::Spec.client.get(Marten.routes.reverse("accounts:session_new"))

      response.status.should eq(200)
      response.content.should contain("email_address")
      response.content.should contain("password")
    end

    it "redirects to first-run when no users exist yet" do
      response = Marten::Spec.client.get(Marten.routes.reverse("accounts:session_new"))

      response.status.should eq(302)
      response.headers["Location"].should eq(Marten.routes.reverse("accounts:first_run_new"))
    end

    # Skipping Rails test "new denied with incompatible browser": Marten port
    # lacks Rails' `allow_browser versions: :modern` middleware — user-agent
    # gating is not implemented. (Dropped with user approval.)
    # Skipping Rails test "new allowed with compatible browser": same reason —
    # no browser-detection middleware to exercise.
  end

  describe "POST /session/create" do
    it "signs the user in with valid credentials" do
      Spec::Factories.create_account
      user = Spec::Factories.create_user(email: "david@example.com")

      response = Marten::Spec.client.post(
        Marten.routes.reverse("accounts:session_create"),
        data: {"email_address" => "david@example.com", "password" => "secret123456"},
      )

      response.status.should eq(302)
      response.headers["Location"].should eq(Marten.routes.reverse("books:index"))
    end

    it "re-renders the form with an error on invalid credentials" do
      Spec::Factories.create_account
      Spec::Factories.create_user(email: "david@example.com")

      response = Marten::Spec.client.post(
        Marten.routes.reverse("accounts:session_create"),
        data: {"email_address" => "david@example.com", "password" => "wrong"},
      )

      response.status.should eq(422)
      response.content.should contain("Invalid email or password")
    end

    it "rejects deactivated users" do
      Spec::Factories.create_account
      Spec::Factories.create_user(email: "ghost@example.com", active: false)

      response = Marten::Spec.client.post(
        Marten.routes.reverse("accounts:session_create"),
        data: {"email_address" => "ghost@example.com", "password" => "secret123456"},
      )

      response.status.should eq(422)
    end
  end

  describe "POST /session/destroy" do
    it "signs the user out and redirects to the sign-in page" do
      Spec::Factories.create_account
      user = Spec::Factories.create_user(email: "david@example.com")
      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, user)

      response = client.post(Marten.routes.reverse("accounts:session_destroy"))

      response.status.should eq(302)
      response.headers["Location"].should eq(Marten.routes.reverse("accounts:session_new"))
    end
  end
end

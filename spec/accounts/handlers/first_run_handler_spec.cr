require "../../spec_helper"

describe "Accounts first-run handlers" do
  describe "GET /first_run" do
    it "renders the first-run form when no account exists yet" do
      response = Marten::Spec.client.get(Marten.routes.reverse("accounts:first_run_new"))

      response.status.should eq(200)
    end

    it "redirects to root when an account already exists" do
      Spec::Factories.create_account
      Spec::Factories.create_user

      response = Marten::Spec.client.get(Marten.routes.reverse("accounts:first_run_new"))

      response.status.should eq(302)
      response.headers["Location"].should eq("/")
    end
  end

  describe "POST /first_run/create" do
    it "creates the first administrator and signs them in" do
      before_count = Accounts::User.all.count

      response = Marten::Spec.client.post(
        Marten.routes.reverse("accounts:first_run_create"),
        data: {
          "name"          => "New Person",
          "email_address" => "new@example.com",
          "password"      => "secret123456",
        },
      )

      Accounts::User.all.count.should eq(before_count + 1)
      response.status.should eq(302)
      response.headers["Location"].should eq(Marten.routes.reverse("books:index"))

      user = Accounts::User.filter(email: "new@example.com").first.not_nil!
      user.administrator?.should be_true
      user.active.should be_true
    end

    it "does not create another user when an account already exists" do
      Spec::Factories.create_account
      Spec::Factories.create_user(email: "existing@example.com")

      before_count = Accounts::User.all.count
      response = Marten::Spec.client.post(
        Marten.routes.reverse("accounts:first_run_create"),
        data: {
          "name"          => "New Person",
          "email_address" => "new@example.com",
          "password"      => "secret123456",
        },
      )

      Accounts::User.all.count.should eq(before_count)
      response.status.should eq(302)
      response.headers["Location"].should eq("/")
    end
  end
end

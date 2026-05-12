require "../../spec_helper"

describe "Accounts join-code handler" do
  describe "POST /account/join_codes" do
    it "regenerates the account's join code when posted by an admin" do
      account = Spec::Factories.create_account
      old_code = account.join_code
      david = Spec::Factories.create_admin(email: "david@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.post(Marten.routes.reverse("accounts:join_codes_create"))

      response.status.should eq(302)
      response.headers["Location"].should eq(Marten.routes.reverse("accounts:users_index"))

      Accounts::Account.first!.join_code.should_not eq(old_code)
    end

    it "forbids non-admin members from regenerating the join code" do
      account = Spec::Factories.create_account
      old_code = account.join_code
      jz = Spec::Factories.create_user(email: "jz@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, jz)

      response = client.post(Marten.routes.reverse("accounts:join_codes_create"))

      response.status.should eq(403)
      Accounts::Account.first!.join_code.should eq(old_code)
    end
  end
end

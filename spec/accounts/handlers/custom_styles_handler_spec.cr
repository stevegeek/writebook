require "../../spec_helper"

describe "Accounts custom styles handler" do
  describe "GET /account/custom_styles" do
    it "renders the custom-styles editor for an admin" do
      Spec::Factories.create_account
      david = Spec::Factories.create_admin(email: "david@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.get(Marten.routes.reverse("accounts:custom_styles_edit"))
      response.status.should eq(200)
    end

    it "forbids non-admin members from viewing the editor" do
      Spec::Factories.create_account
      kevin = Spec::Factories.create_user(email: "kevin@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, kevin)

      response = client.get(Marten.routes.reverse("accounts:custom_styles_edit"))
      response.status.should eq(403)
    end
  end

  describe "POST /account/custom_styles" do
    it "saves the submitted CSS onto the singleton account" do
      Spec::Factories.create_account
      david = Spec::Factories.create_admin(email: "david@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.post(
        Marten.routes.reverse("accounts:custom_styles_edit"),
        data: {"custom_styles" => ":root { --color-text: red; }"},
      )

      response.status.should eq(302)
      response.headers["Location"].should eq(Marten.routes.reverse("accounts:custom_styles_edit"))

      Accounts::Account.first!.custom_styles.should eq(":root { --color-text: red; }")
    end

    it "forbids non-admins from updating" do
      Spec::Factories.create_account
      kevin = Spec::Factories.create_user(email: "kevin@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, kevin)

      response = client.post(
        Marten.routes.reverse("accounts:custom_styles_edit"),
        data: {"custom_styles" => ":root { --color-text: red; }"},
      )

      response.status.should eq(403)
    end
  end
end

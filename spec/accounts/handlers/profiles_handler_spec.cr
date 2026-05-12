require "../../spec_helper"

describe "Accounts profile handlers" do
  describe "GET /users/<id>/profile" do
    it "renders the profile of the signed-in user themselves" do
      Spec::Factories.create_account
      david = Spec::Factories.create_admin(email: "david@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.get(Marten.routes.reverse("accounts:profile_show_user", id: david.pk!))
      response.status.should eq(200)
    end

    it "lets an admin view another user's profile" do
      Spec::Factories.create_account
      david = Spec::Factories.create_admin(email: "david@example.com")
      kevin = Spec::Factories.create_user(email: "kevin@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.get(Marten.routes.reverse("accounts:profile_show_user", id: kevin.pk!))
      response.status.should eq(200)
    end

    it "forbids a non-admin from viewing another user's profile" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      kevin = Spec::Factories.create_user(email: "kevin@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, kevin)

      response = client.get(Marten.routes.reverse("accounts:profile_show_user", id: david.pk!))
      response.status.should eq(403)
    end
  end

  describe "GET /users/<id>/profile/edit" do
    it "is accessible to the user themselves" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.get(Marten.routes.reverse("accounts:profile_edit_user", id: david.pk!))
      response.status.should eq(200)
    end

    it "forbids a non-admin from editing another user's profile" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      kevin = Spec::Factories.create_user(email: "kevin@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.get(Marten.routes.reverse("accounts:profile_edit_user", id: kevin.pk!))
      response.status.should eq(403)
    end
  end

  describe "POST /users/<id>/profile/edit" do
    it "lets a user modify their own profile" do
      Spec::Factories.create_account
      kevin = Spec::Factories.create_user(email: "kevin@example.com", name: "Kevin")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, kevin)

      response = client.post(
        Marten.routes.reverse("accounts:profile_edit_user", id: kevin.pk!),
        data: {
          "name"          => "Bob",
          "email_address" => kevin.email.to_s,
        },
      )

      response.status.should eq(302)
      response.headers["Location"].should eq(Marten.routes.reverse("accounts:users_index"))

      kevin.reload
      kevin.name.should eq("Bob")
    end

    it "forbids modifying another user's profile when not an admin" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com", name: "David")
      kevin = Spec::Factories.create_user(email: "kevin@example.com", name: "Kevin")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.post(
        Marten.routes.reverse("accounts:profile_edit_user", id: kevin.pk!),
        data: {
          "name"          => "Bob",
          "email_address" => kevin.email.to_s,
        },
      )

      response.status.should eq(403)

      kevin.reload
      kevin.name.should eq("Kevin")
    end
  end
end

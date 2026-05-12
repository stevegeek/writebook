module Spec
  # Sign-in helpers for handler specs — the Marten-side analog of Rails'
  # SessionTestHelper. Drives the real /session/create endpoint via the
  # given test client so the session cookie + middleware path is exercised
  # exactly like a real browser hit.
  module Sessions
    extend self

    # Sign the given user in on `client`. Asserts the response was a
    # redirect (302) and that a session cookie was set, then returns the
    # user. Pass `password:` if the user was created with a non-default one.
    def sign_in_as(client : Marten::Spec::Client, user : Accounts::User, password : String = "secret123456") : Accounts::User
      response = client.post(
        Marten.routes.reverse("accounts:session_create"),
        data: {"email_address" => user.email.to_s, "password" => password},
      )
      unless response.status == 302
        raise "sign_in_as failed for #{user.email.inspect}: status=#{response.status} body=#{response.content[0, 200]}"
      end
      user
    end

    def sign_out(client : Marten::Spec::Client) : Nil
      client.post(Marten.routes.reverse("accounts:session_destroy"))
    end
  end
end

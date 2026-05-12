require "./spec_helper"

# Tier-2 smoke: validates that the spec process, the spawned bin/server, the
# shared SQLite tempfile, headless Chrome, and the DSL shim all line up before
# we layer real Rails-port system specs on top.
describe "System spec smoke test" do
  it "renders the sign-in form" do
    Spec::Factories.create_account
    Spec::Factories.create_user(email: "smoke@example.com")

    visit "/session/new"
    assert_text "Sign in"
  end

  it "signs in and lands on the books index" do
    Spec::Factories.create_account
    user = Spec::Factories.create_user(email: "kevin@example.com")

    sign_in user

    assert_current_path "/books"
  end
end

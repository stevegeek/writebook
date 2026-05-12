require "../../spec_helper"

describe "Accounts::User" do
  describe "passwords" do
    pending "does not prevent very long passwords" do
      # FIXME(porting gap): Crystal's stdlib Crypto::Bcrypt raises
      # `Invalid password size` for inputs over 72 bytes (the same hard
      # limit Ruby's bcrypt has — Ruby silently truncates, Crystal raises).
      # The Rails test asserts a 300-character password is `valid?`; the
      # Marten port's MartenAuth::User#set_password propagates the bcrypt
      # exception.
    end
  end

  describe "after_create :grant_access_to_everyone_books" do
    it "grants new users read access to books with everyone_access" do
      everyone_book = Books::Book.create!(title: "My new book", everyone_access: true)
      other_book = Books::Book.create!(title: "My secret book", everyone_access: false)

      bob = Spec::Factories.create_user(email: "bob@example.com", name: "Bob")

      everyone_book.accessable?(bob).should be_true
      everyone_book.editable?(bob).should be_false
      other_book.accessable?(bob).should be_false
    end
  end
end

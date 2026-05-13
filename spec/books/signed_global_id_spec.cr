require "../spec_helper"

# Inline port of Rails' GlobalID::Locator.locate_signed. Covers the
# sign → locate round-trip + every reason a token can be rejected.
describe Books::SignedGlobalId do
  describe ".sign and .locate" do
    it "round-trips a Book through the default purpose" do
      book = Spec::Factories.create_book(title: "Handbook")
      token = Books::SignedGlobalId.sign(book)

      found = Books::SignedGlobalId.locate(token)
      found.should_not be_nil
      found.as(Books::Book).pk.should eq(book.pk)
    end

    it "namespaces tokens by purpose — wrong purpose returns nil" do
      book = Spec::Factories.create_book(title: "Handbook")
      token = Books::SignedGlobalId.sign(book, purpose: "markdown_upload")

      Books::SignedGlobalId.locate(token, purpose: "session_transfer").should be_nil
      Books::SignedGlobalId.locate(token, purpose: "markdown_upload").not_nil!.pk.should eq(book.pk)
    end

    it "rejects an expired token" do
      book = Spec::Factories.create_book(title: "Handbook")
      # Signed.sign accepts Time::Span; an effectively-zero span expires
      # the token immediately (the signer compares against Time.utc on verify).
      token = Books::SignedGlobalId.sign(book, expires_in: -1.second)
      Books::SignedGlobalId.locate(token).should be_nil
    end

    it "returns nil on a tampered/garbage token" do
      Books::SignedGlobalId.locate("garbage").should be_nil
      Books::SignedGlobalId.locate("").should be_nil
      Books::SignedGlobalId.locate(nil).should be_nil
    end

    it "returns nil when the resolved class isn't in the allowlist" do
      # Construct a payload that signs cleanly but names an unknown class.
      payload = {"c" => "Accounts::User", "i" => "1", "p" => "default"}.to_json
      forged = Marten::Core::Signer.new.sign(payload, expires: nil)
      Books::SignedGlobalId.locate(forged).should be_nil
    end

    it "returns nil when the resolved record no longer exists" do
      book = Spec::Factories.create_book(title: "Handbook")
      token = Books::SignedGlobalId.sign(book)
      book.delete
      Books::SignedGlobalId.locate(token).should be_nil
    end

    it "round-trips a leafable Page" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(book: book, title: "P", body: "x")
      page = leaf.page.not_nil!

      token = Books::SignedGlobalId.sign(page, purpose: "markdown_upload")
      found = Books::SignedGlobalId.locate(token, purpose: "markdown_upload")
      found.as(Books::Leafables::Page).pk.should eq(page.pk)
    end
  end

  describe "HasIt mixin" do
    it "is included on Book and Markdown" do
      book = Spec::Factories.create_book(title: "T")
      book.responds_to?(:signed_global_id).should be_true

      page = Books::Leafables::Page.create!
      page.body = "x"
      md = Books::Markdown.filter(record_type: "Books::Leafables::Page", record_id: page.pk!).first.not_nil!
      md.responds_to?(:signed_global_id).should be_true
    end

    it "instance method delegates to the module sign" do
      book = Spec::Factories.create_book(title: "T")
      token = book.signed_global_id(purpose: "markdown_upload")
      Books::SignedGlobalId.locate(token, purpose: "markdown_upload").not_nil!.pk.should eq(book.pk)
    end
  end
end

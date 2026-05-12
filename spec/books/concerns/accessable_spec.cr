require "../../spec_helper"

describe "Books::Accessable" do
  describe ".accessable_or_published" do
    it "returns published books only when no user is given" do
      published = Spec::Factories.create_book(title: "Published", published: true)
      Spec::Factories.create_book(title: "Hidden")

      visible = Books::Book.accessable_or_published(nil).to_a
      visible.map(&.pk).should contain(published.pk)
      visible.size.should eq(1)
    end

    it "returns books the user has access to OR are published" do
      kevin = Spec::Factories.create_user(email: "kevin@example.com")
      handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
      manual = Spec::Factories.create_book(title: "Manual", published: true)
      Spec::Factories.create_book(title: "Hidden")

      visible = Books::Book.accessable_or_published(kevin).to_a.map(&.pk)
      visible.should contain(handbook.pk)
      visible.should contain(manual.pk)
      visible.size.should eq(2)
    end
  end

  describe ".with_everyone_access" do
    it "returns only books flagged everyone_access" do
      open_book = Spec::Factories.create_book(title: "Open", everyone_access: true)
      Spec::Factories.create_book(title: "Closed", everyone_access: false)

      ids = Books::Book.with_everyone_access.to_a.map(&.pk)
      ids.should contain(open_book.pk)
      ids.size.should eq(1)
    end
  end

  describe "#update_access" do
    it "grants editor access" do
      kevin = Spec::Factories.create_user(email: "kevin@example.com")
      book = Spec::Factories.create_book(title: "My new book")

      book.update_access(editor_ids: [kevin.pk.not_nil!.to_i64], reader_ids: [] of Int64)

      book.editable?(kevin).should be_true
    end

    it "updates an existing access from editor to reader" do
      kevin = Spec::Factories.create_user(email: "kevin@example.com")
      book = Spec::Factories.create_book(title: "My new book")

      book.update_access(editor_ids: [kevin.pk.not_nil!.to_i64], reader_ids: [] of Int64)
      book.editable?(kevin).should be_true

      book.update_access(editor_ids: [] of Int64, reader_ids: [kevin.pk.not_nil!.to_i64])
      book.accessable?(kevin).should be_true
      book.editable?(kevin).should be_false
    end

    it "removes stale accesses" do
      kevin = Spec::Factories.create_user(email: "kevin@example.com")
      jz = Spec::Factories.create_user(email: "jz@example.com")
      book = Spec::Factories.create_book(title: "My new book")

      book.update_access(
        editor_ids: [kevin.pk.not_nil!.to_i64],
        reader_ids: [jz.pk.not_nil!.to_i64],
      )
      Accounts::Access.filter(book_id: book.pk).count.should eq(2)

      book.update_access(
        editor_ids: [kevin.pk.not_nil!.to_i64],
        reader_ids: [] of Int64,
      )
      Accounts::Access.filter(book_id: book.pk).count.should eq(1)
    end

    pending "everyone_access: grants implicit reader access to all active users" do
      # FIXME(porting gap): The Marten port's update_access(editor_ids:, reader_ids:)
      # doesn't take an `everyone_access:` flag, and the concern reads the
      # field off the Book itself. The Rails test set everyone_access on
      # the Book and then called update_access(editors: [], readers: []);
      # the Marten equivalent path would need an interface decision around
      # whether `update_access` also flips the `everyone_access` field.
    end
  end

  describe "#editable?" do
    it "is true for administrators regardless of explicit access" do
      admin = Spec::Factories.create_admin(email: "admin@example.com")
      book = Spec::Factories.create_book(title: "Anything")

      book.editable?(admin).should be_true
    end

    it "is false for a member without access" do
      bob = Spec::Factories.create_user(email: "bob@example.com")
      book = Spec::Factories.create_book(title: "Locked")

      book.editable?(bob).should be_false
    end

    it "is false when no user is given" do
      book = Spec::Factories.create_book(title: "Anon")

      book.editable?(nil).should be_false
    end
  end

  describe "#accessable?" do
    it "is true when the user has an explicit Access row" do
      kevin = Spec::Factories.create_user(email: "kevin@example.com")
      book = Spec::Factories.create_book(title: "Hand", editor: kevin)

      book.accessable?(kevin).should be_true
    end

    it "is false when no user is given" do
      book = Spec::Factories.create_book(title: "Anon")

      book.accessable?(nil).should be_false
    end
  end
end

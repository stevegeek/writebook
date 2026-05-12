module Spec
  # Lightweight factory helpers — the test-side equivalent of Rails' YAML
  # fixtures. Each method creates the minimum valid record and returns it.
  # Pass keyword arguments to override any field.
  module Factories
    extend self

    # ---------------- Accounts ----------------

    def create_account(name : String = "Writebook") : Accounts::Account
      Accounts::Account.create_with_defaults!(name)
    end

    def create_user(
      email : String = "user-#{Random::Secure.hex(4)}@example.com",
      name : String = "Test User",
      password : String = "secret123456",
      role : String = "member",
      active : Bool = true,
    ) : Accounts::User
      user = Accounts::User.new(name: name, email: email, role: role, active: active)
      user.set_password(password)
      user.save!
      user
    end

    def create_admin(
      email : String = "admin-#{Random::Secure.hex(4)}@example.com",
      name : String = "Admin",
      password : String = "secret123456",
      active : Bool = true,
    ) : Accounts::User
      create_user(email: email, name: name, password: password, role: "administrator", active: active)
    end

    def create_access(
      user : Accounts::User,
      book : Books::Book,
      level : String = "reader",
    ) : Accounts::Access
      Accounts::Access.create!(user_id: user.pk, book_id: book.pk, level: level)
    end

    # ---------------- Books ----------------

    def create_book(
      title : String = "Test Book #{Random::Secure.hex(4)}",
      author : String? = "Test Author",
      published : Bool = false,
      everyone_access : Bool = false,
      editor : Accounts::User? = nil,
    ) : Books::Book
      book = Books::Book.create!(
        title: title,
        author: author,
        published: published,
        everyone_access: everyone_access,
      )
      if editor
        Accounts::Access.create!(user_id: editor.pk, book_id: book.pk, level: "editor")
      end
      book
    end

    # Build a Page leafable + wrapping Leaf in one shot. Returns the Leaf so
    # callers can use `leaf.page` / `leaf.title` / etc.
    def create_page_leaf(
      book : Books::Book,
      title : String = "Page #{Random::Secure.hex(4)}",
      body : String = "Page body content",
      position_score : Float64 = next_position_score(book),
    ) : Books::Leaf
      page = Books::Leafables::Page.create!
      page.body = body
      Books::Leaf.create!(
        book_id: book.pk,
        leafable_type: "Books::Leafables::Page",
        leafable_id: page.pk,
        title: title,
        position_score: position_score,
        status: "active",
      )
    end

    def create_section_leaf(
      book : Books::Book,
      title : String = "Section #{Random::Secure.hex(4)}",
      body : String? = "Section body",
      theme : String? = nil,
      position_score : Float64 = next_position_score(book),
    ) : Books::Leaf
      section = Books::Leafables::Section.create!(body: body, theme: theme)
      Books::Leaf.create!(
        book_id: book.pk,
        leafable_type: "Books::Leafables::Section",
        leafable_id: section.pk,
        title: title,
        position_score: position_score,
        status: "active",
      )
    end

    def create_picture_leaf(
      book : Books::Book,
      title : String = "Picture #{Random::Secure.hex(4)}",
      caption : String? = nil,
      position_score : Float64 = next_position_score(book),
    ) : Books::Leaf
      picture = Books::Leafables::Picture.create!(caption: caption)
      Books::Leaf.create!(
        book_id: book.pk,
        leafable_type: "Books::Leafables::Picture",
        leafable_id: picture.pk,
        title: title,
        position_score: position_score,
        status: "active",
      )
    end

    # Mirrors Rails Edit (revision/trash log row).
    def create_edit(
      leaf : Books::Leaf,
      event : String = "revision",
    ) : Books::Edit
      target = leaf.leafable
      Books::Edit.create!(
        leaf_id: leaf.pk,
        leafable_type: leaf.leafable_type,
        leafable_id: target.try(&.pk),
        event: event,
      )
    end

    # Next position_score for a book, monotonically increasing in 1.0 steps.
    # Mirrors Positionable's append-to-end semantics without forcing callers
    # to know the internal score scheme.
    def next_position_score(book : Books::Book) : Float64
      last = Books::Leaf.filter(book_id: book.pk).order("-position_score").first
      last.nil? ? 1.0 : (last.position_score.not_nil! + 1.0)
    end
  end
end

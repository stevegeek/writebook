# `script/manage seed_manual` — populates the Writebook Manual demo book.
#
# Mirrors Rails Writebook's `DemoContent.create_manual(user)` (seeded on
# first_run). Reads markdown files from `src/books/seed/demo/*.md`, parses
# YAML front-matter (`title:`, optional `class: Section` + `theme:`), and
# creates a Page or Section per file, wrapped in a Leaf.
#
# Idempotent: skips if the manual book already exists. Pass `--force` to
# delete and re-create.
#
# The book is owned by the first administrator user found.
class Books::SeedManualCommand < Marten::CLI::Command
  command_name :seed_manual
  help "Seed the Writebook Manual demo book (14 leaves)"

  @force : Bool = false

  def setup
    on_option("f", "force", "Delete and re-create if the manual already exists") { @force = true }
  end

  def run
    admin = ::Accounts::User.filter(role: "administrator", active: true).first
    if admin.nil?
      print(style("No administrator user found. Visit /first_run first.", fore: :red))
      return
    end

    existing = ::Books::Book.filter(title: "The Writebook Manual").first
    if existing
      if @force
        print("Removing existing manual book…")
        existing.delete
      else
        print(style("Manual book already exists. Pass --force to re-create.", fore: :yellow))
        return
      end
    end

    print("Creating book…")
    book = ::Books::Book.create!(
      title: "The Writebook Manual",
      author: "37signals",
      everyone_access: true,
    )

    # Grant the seeding admin editor access. `accessable_or_published` only
    # includes books with a direct `Access` row (or `published=true`); without
    # this row, a re-seeded Manual would silently disappear from the admin's
    # library since the new-user `grant_access_to_everyone_books` callback
    # only fires for users created AFTER the book exists.
    ::Accounts::Access.create!(book: book, user: admin, level: "editor")

    attach_cover(book)

    seed_dir = Path["src/books/seed/demo"].expand.to_s
    files = Dir.glob(File.join(seed_dir, "*.md")).sort
    print("Loading #{files.size} markdown files from #{seed_dir}…")

    files.each_with_index do |path, idx|
      front_matter, body = parse_front_matter(File.read(path))
      title = front_matter["title"]? || File.basename(path, ".md")

      if front_matter["class"]? == "Section"
        # Sections may carry a `theme: dark` front-matter key (the Appendix
        # uses it to render white-on-black, mirroring Rails' demo content).
        theme = front_matter["theme"]?
        section = ::Books::Leafables::Section.create!(body: body, theme: theme)
        ::Books::Leaf.create!(
          book: book,
          leafable: section,
          title: title,
          status: "active",
          position_score: (idx + 1).to_f64,
        )
      else
        page = ::Books::Leafables::Page.create!
        page.body = body  # has_markdown setter — saves a Markdown row
        ::Books::Leaf.create!(
          book: book,
          leafable: page,
          title: title,
          status: "active",
          position_score: (idx + 1).to_f64,
        )
      end
      print("  + #{File.basename(path)} → \"#{title}\"")
    end

    print(style("Done. Book id: #{book.pk}", fore: :green))
  end

  # Build a Marten::HTTP::UploadedFile from the demo cover jpg on disk and
  # attach it as the book's "cover" attachment, matching the variants shape
  # used by BooksNewHandler/BooksEditHandler (BookCoverUploadHelpers).
  private def attach_cover(book : ::Books::Book) : Nil
    cover_path = Path["src/assets/images/demo/writebook-manual.jpg"].expand.to_s
    unless ::File.exists?(cover_path)
      print(style("Cover asset not found at #{cover_path}; skipping cover attach.", fore: :yellow))
      return
    end

    filename = ::File.basename(cover_path)
    content_disposition = "form-data; name=\"image\"; filename=\"#{filename}\""
    part_headers = HTTP::Headers{"Content-Disposition" => content_disposition, "Content-Type" => "image/jpeg"}

    ::File.open(cover_path, "rb") do |io|
      part = HTTP::FormData::Part.new(headers: part_headers, body: io)
      uploaded = Marten::HTTP::UploadedFile.new(part)
      ::Books::AttachmentHelpers.attach(
        record: book,
        name: "cover",
        uploaded_file: uploaded,
        variants: {"thumbnail" => {max_dimension: 600}},
      )
    end
    print("  + cover attached (writebook-manual.jpg)")
  end

  # Tiny YAML front-matter parser. Splits on the first `---\n…\n---\n`,
  # parses keys via line-by-line `key: value`. Avoids depending on a YAML
  # shard for this trivial use.
  private def parse_front_matter(content : String) : {Hash(String, String), String}
    if content.starts_with?("---\n")
      end_idx = content.index("\n---\n", 4)
      if end_idx
        front = content[4...end_idx]
        body = content[(end_idx + 5)..]
        return {parse_yaml_keys(front), body}
      end
    end
    empty = {} of String => String
    {empty, content}
  end

  private def parse_yaml_keys(text : String) : Hash(String, String)
    result = {} of String => String
    text.each_line do |line|
      next if line.strip.empty?
      key, _, value = line.partition(":")
      next if value.empty?
      result[key.strip] = value.strip.lchop('"').rchop('"')
    end
    result
  end
end

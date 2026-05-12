# Module-level helpers for attaching files to records via the polymorphic
# `Attachment` model. Replaces the Active-Storage-style `has_one_attached` /
# `has_many_attached` macros.
#
# Basic upload:
#
#   AttachmentHelpers.attach(record: book, name: "cover", uploaded_file: uploaded)
#
# With variants (pre-computed at upload time via crystal-vips):
#
#   AttachmentHelpers.attach(
#     record: picture, name: "image", uploaded_file: uploaded,
#     variants: {"large" => {max_dimension: 1500}},
#   )
#
# Lookups:
#
#   AttachmentHelpers.find_one(record: book, name: "cover")
#   AttachmentHelpers.find_many(record: markdown, name: "uploads")
#   AttachmentHelpers.variant_of(attachment, kind: "large")
module Books::AttachmentHelpers
  extend self

  alias RecordType = Book | Leafables::Picture | Markdown

  alias VariantSpec = NamedTuple(max_dimension: Int32)

  # Attach a file to a record. Returns the saved Attachment row.
  # If variants are provided, additionally creates one Attachment row per
  # variant kind, each pointing at the original via `variant_of_id`.
  def attach(
    record : RecordType,
    name : String,
    uploaded_file : Marten::HTTP::UploadedFile,
    variants : Hash(String, VariantSpec) = {} of String => VariantSpec,
  ) : Attachment
    # UploadedFile has no #content_type accessor (content_type comes from
    # the Part headers which aren't exposed publicly). Store nil; the
    # caller can update after the fact if needed.
    original = Attachment.new(
      record: record,
      name: name,
      content_type: nil,
      byte_size: uploaded_file.size.to_i64,
    )
    original.file = uploaded_file
    original.save!

    variants.each do |kind, spec|
      compute_and_save_variant(original, kind, spec)
    end

    original
  end

  # Resolve a single attachment for a record + name (e.g. Book cover).
  # Returns the most recently created original (non-variant).
  def find_one(record : RecordType, name : String) : Attachment?
    Attachment
      .filter(record_type: record.class.name, record_id: record.pk)
      .filter(name: name)
      .filter(variant_of_id: nil)
      .order("-created_at")
      .first
  end

  def find_many(record : RecordType, name : String) : Array(Attachment)
    Attachment
      .filter(record_type: record.class.name, record_id: record.pk)
      .filter(name: name)
      .filter(variant_of_id: nil)
      .order(:created_at)
      .to_a
  end

  def variant_of(original : Attachment, kind : String) : Attachment?
    Attachment
      .filter(variant_of_id: original.pk)
      .filter(variation_kind: kind)
      .first
  end

  # Pipe the original through crystal-vips (resize-to-fit) and save a new
  # Attachment row pointing at the original. Falls back to a no-op if the
  # original isn't an image vips can read.
  private def compute_and_save_variant(original : Attachment, kind : String, spec : VariantSpec) : Nil
    original_file = original.file
    return if original_file.name.nil?

    temp_path = ::File.tempname("variant_#{kind}_", ::File.extname(original_file.name.not_nil!))

    # original_file.open delegates to the storage backend and returns an IO.
    # No block form — we must close it manually.
    source_io = original_file.open
    begin
      ::File.open(temp_path, "wb") { |f| IO.copy(source_io, f) }
    ensure
      source_io.close
    end

    image = Vips::Image.new_from_file(temp_path)
    max_dim = spec[:max_dimension]
    scale = Math.min(max_dim.to_f / image.width, max_dim.to_f / image.height)
    resized = scale < 1.0 ? image.resize(scale) : image

    variant_path = "#{temp_path}.variant.jpg"
    resized.write_to_file(variant_path)

    variant_filename = "#{::File.basename(original_file.name.not_nil!, ::File.extname(original_file.name.not_nil!))}_#{kind}.jpg"

    # Build a FormData::Part with a proper Content-Disposition header so
    # Marten::HTTP::UploadedFile can parse the filename.
    content_disposition = "form-data; name=\"file\"; filename=\"#{variant_filename}\""
    part_headers = HTTP::Headers{"Content-Disposition" => content_disposition, "Content-Type" => "image/jpeg"}

    ::File.open(variant_path, "rb") do |variant_io|
      part = HTTP::FormData::Part.new(headers: part_headers, body: variant_io)
      uploaded = Marten::HTTP::UploadedFile.new(part)
      variant = Attachment.new(
        record: original.record!,
        name: original.name,
        variant_of: original,
        variation_kind: kind,
        content_type: "image/jpeg",
        byte_size: ::File.size(variant_path).to_i64,
      )
      variant.file = uploaded
      variant.save!
    end

    ::File.delete?(temp_path)
    ::File.delete?(variant_path)
  rescue ex
    # Original isn't a vips-readable image (e.g. PDF, plain text); skip
    # variant generation silently. The original is still saved.
    Marten::Log.warn { "Skipping variant '#{kind}' for attachment #{original.pk}: #{ex.message}" }
  end
end

module Books
  class PictureSchema < Marten::Schema
    # Title comes from the leafable edit-header nav input (form="leafable-editor").
    # On `new`, it falls back to caption in the handler if blank.
    field :title, :string, max_size: 255, required: false
    field :caption, :string, max_size: 1024, required: false
    # Image is OPTIONAL on the schema so that:
    #   - the inline-create flow (creates an empty Picture, then user lands on
    #     edit) can save title/caption without re-uploading,
    #   - the edit form can update caption/title without re-uploading the image.
    # Handlers enforce "image required on first save" themselves.
    field :image, :file, required: false
  end
end

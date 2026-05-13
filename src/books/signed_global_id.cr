require "json"

module Books
  # Tiny port of `GlobalID::Locator.locate_signed` for the markdown-upload
  # endpoint. Rails' `GlobalID` encodes `(model_class_name, pk)` in an
  # HMAC-signed token so a single endpoint can attach files to *any* host
  # model that owns a `has_markdown` attribute — without the controller
  # knowing the concrete class.
  #
  # Crystal can't `constantize` a runtime string into a class (closed-set
  # at compile time), so this module requires an explicit `ALLOWED` map
  # of class names to classes. Models that want to participate include
  # `Books::SignedGlobalId::HasIt` and call `record.signed_global_id`.
  #
  # Payload shape (JSON, HMAC-signed via `Marten::Core::Signer`):
  #
  #     {"c": "Books::Book", "i": "3", "p": "markdown_upload"}
  #
  # Verifier checks: signature, expiry (if set), and purpose match. The
  # allowlist gates which classes the resolver will instantiate (a
  # poisoned token referencing some other model class returns nil).
  #
  # Inline now; once a second consumer needs it, extract to
  # `marten-global-id` alongside marten-signed-id (which already provides
  # the single-model-known-at-call-site variant).
  module SignedGlobalId
    PURPOSE_DEFAULT = "default"

    # Allowlist of classes that participate. Add a `when` branch here when
    # a new model includes `Books::SignedGlobalId::HasIt`. A case-when
    # avoids the constant-initialization load order issue: this module
    # loads before models are parsed, so a Hash literal referencing
    # Books::Book at module load time would force a circular require.
    private def self.resolve_class(name : String) : Marten::DB::Model.class | Nil
      case name
      when "Books::Book"               then Books::Book
      when "Books::Markdown"           then Books::Markdown
      when "Books::Leafables::Page"    then Books::Leafables::Page
      when "Books::Leafables::Section" then Books::Leafables::Section
      when "Books::Leafables::Picture" then Books::Leafables::Picture
      else                                  nil
      end
    end

    # Sign a `(class_name, pk)` tuple with HMAC + optional expiry,
    # namespaced by `purpose`. Mirrors `SignedGlobalID#to_s` (which calls
    # `verifier.generate(uri, purpose:, expires_at:)`).
    def self.sign(
      record : Marten::DB::Model,
      purpose : String = PURPOSE_DEFAULT,
      expires_in : Time::Span? = nil,
    ) : String
      payload = {"c" => record.class.name, "i" => record.pk!.to_s, "p" => purpose}.to_json
      expires = expires_in.try { |span| Time.utc + span }
      Marten::Core::Signer.new.sign(payload, expires: expires)
    end

    # Verify + decode a signed token, returning the resolved record (or nil
    # on any failure: bad sig, expired, purpose mismatch, unknown class,
    # record missing). Mirrors `GlobalID::Locator.locate_signed`.
    def self.locate(token : String?, purpose : String = PURPOSE_DEFAULT) : Marten::DB::Model?
      return nil if token.nil? || token.empty?

      data = Marten::Core::Signer.new.unsign(token)
      return nil if data.nil?

      parsed = JSON.parse(data).as_h? rescue nil
      return nil if parsed.nil?

      return nil unless parsed["p"]?.try(&.as_s) == purpose

      class_name = parsed["c"]?.try(&.as_s)
      id_str = parsed["i"]?.try(&.as_s)
      return nil if class_name.nil? || id_str.nil?

      klass = resolve_class(class_name)
      return nil if klass.nil?

      klass.get(pk: id_str)
    end

    # Instance-side mixin. Adds `record.signed_global_id(purpose:, expires_in:)`.
    # Mirrors Rails' `GlobalID::Identification` (which adds `to_global_id` +
    # `to_signed_global_id`). Include in every class that needs to issue
    # signed tokens — and remember to also add the class name to ALLOWED.
    module HasIt
      def signed_global_id(
        purpose : ::String = ::Books::SignedGlobalId::PURPOSE_DEFAULT,
        expires_in : ::Time::Span? = nil,
      ) : ::String
        ::Books::SignedGlobalId.sign(self, purpose, expires_in)
      end
    end
  end
end

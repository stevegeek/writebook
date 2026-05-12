require "../spec_helper"

# Ports `writebook-rails/test/models/qr_code_link_test.rb`.
#
# Rails defined a `QrCodeLink` value object that wrapped a URL and could
# `signed` it (via Rails' MessageVerifier) for round-tripping through a
# QR-code link.  The Marten port does not have a `QrCodeLink` per se —
# its QR features are split across two places:
#
#   1. `Accounts::QrCodeHandler` (`src/accounts/handlers/qr_code_handler.cr`)
#      renders an SVG QR via the `goban` shard.  It encodes a plain join
#      URL — no signing layer.  Public-by-join-code only.
#   2. `Accounts::TransferToken` (`src/accounts/handlers/sessions_transfers_handler.cr`)
#      signs a user ID with `Marten::Core::Signer` + an expiry, then
#      base64url-wraps it for safe URL embedding.  The
#      `SessionsTransfersQrHandler` renders that whole signed URL as a
#      QR.  This is the closest analog to Rails' `QrCodeLink` — a token
#      generator that round-trips through a URL with HMAC verification.
#
# We test the sign/verify round-trip on `TransferToken`, plus the SVG
# QR-code rendering pipeline (goban) the QR handler uses.
describe "QR-code link signing (port of Rails QrCodeLinkTest)" do
  describe "Accounts::TransferToken (Marten counterpart of Rails QrCodeLink)" do
    it "can sign and verify a token round-trip" do
      Spec::Factories.create_account
      user = Spec::Factories.create_user(email: "qr@example.com")

      token = Accounts::TransferToken.generate(user)
      verified = Accounts::TransferToken.verify(token)

      verified.should eq(user.pk.to_s)
    end

    it "returns nil for an invalid/tampered token" do
      Accounts::TransferToken.verify("not-a-real-token").should be_nil
    end

    it "returns nil when the base64url envelope is malformed" do
      # `verify` rescues Base64::Error and returns nil rather than raising.
      Accounts::TransferToken.verify("@@@@ not base64 @@@@").should be_nil
    end

    it "produces a URL-safe token (no '+', '/', '=' or '--' separator)" do
      Spec::Factories.create_account
      user = Spec::Factories.create_user(email: "safe@example.com")

      token = Accounts::TransferToken.generate(user)
      token.should_not contain("+")
      token.should_not contain("/")
      token.should_not contain("=")
      token.should_not contain("--")
    end
  end

  describe "QR SVG rendering (the goban path used by QrCodeHandler)" do
    it "produces an SVG document for an arbitrary URL" do
      qr  = Goban::QR.encode_string("https://example.com/join/abc123")
      svg = Goban::SVGExporter.svg_string(qr, 4)

      svg.should contain("<svg")
      svg.should contain("</svg>")
    end
  end

  pending "Rails QrCodeLink.from_signed round-trips an arbitrary URL string" do
    # FIXME(porting gap): The Rails `QrCodeLink` signed an arbitrary URL
    # string and validated it on the way back. The Marten port's
    # `TransferToken` signs a user *ID*, not a URL — the QR endpoint
    # then composes the URL from the verified ID. There is no
    # general-purpose "sign this URL" helper. If we ever need one,
    # `Marten::Core::Signer` + base64url is the same building block
    # `TransferToken` uses.
  end
end

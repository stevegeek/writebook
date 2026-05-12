module Accounts
  # Helpers shared between the two transfer handlers.
  module TransferToken
    EXPIRY = Time::Span.new(hours: 4)

    # Signs the user's ID string with an expiry.  Returns a URL-safe opaque
    # string by base64url-encoding the entire signed token.  This wraps the
    # whole `data--hmac` string in a second base64url layer so the `--`
    # separator and any base64 `+/=` characters never appear bare in a URL
    # path segment.
    def self.generate(user : User) : String
      signer = Marten::Core::Signer.new(key: "transfer/" + Marten.settings.secret_key)
      raw = signer.sign(user.id.to_s, expires: Time.local + EXPIRY)
      Base64.urlsafe_encode(raw, padding: false)
    end

    # Decodes the URL-safe wrapper and verifies the inner signed token.
    # Returns the user ID string if valid and un-expired, nil otherwise.
    def self.verify(token : String) : String?
      signer = Marten::Core::Signer.new(key: "transfer/" + Marten.settings.secret_key)
      inner = Base64.decode_string(token)
      signer.unsign(inner)
    rescue Base64::Error
      nil
    end
  end

  # GET /session/transfer/<token:str>
  # Landing page for the receiving device.  Shows the target user name and a
  # "Sign in" button (a POST form).  Auto-submits via Stimulus on page load
  # (mimicking Rails' auto_submit_form_with pattern).
  class SessionsTransfersShowHandler < Marten::Handler
    def get
      raw_token = params["token"].to_s
      user_id_str = TransferToken.verify(raw_token)
      return head(:bad_request) if user_id_str.nil?

      user = User.filter(active: true).get(id: user_id_str.to_i64)
      return head(:bad_request) if user.nil?

      redeem_url = Marten.routes.reverse("accounts:transfers_redeem", token: raw_token)
      render("sessions/transfers/show.html", context: {user: user, redeem_url: redeem_url})
    end
  end

  # POST /session/transfer/<token:str>
  # Redeems the token: validates, signs the visiting browser in, redirects to root.
  class SessionsTransfersRedeemHandler < Marten::Handler
    def post
      raw_token = params["token"].to_s
      user_id_str = TransferToken.verify(raw_token)
      return head(:bad_request) if user_id_str.nil?

      user = User.filter(active: true).get(id: user_id_str.to_i64)
      return head(:bad_request) if user.nil?

      MartenAuth.sign_in(request, user)
      redirect("/")
    end
  end

  # GET /session/transfer/<token:str>/qr
  # SVG QR code that encodes the *full* transfer URL. Mirrors Rails'
  # `qr_code_image(url)` helper inside `app/views/users/_transfer.html.erb`.
  # Cached for 1 year — same URL produces the same QR code.
  class SessionsTransfersQrHandler < Marten::Handler
    include AuthenticationHelpers

    before_dispatch :require_authentication

    def get
      raw_token = params["token"].to_s
      user_id_str = TransferToken.verify(raw_token)
      return head(:not_found) if user_id_str.nil?

      transfer_url = "#{request.scheme}://#{request.host}" \
                     "#{Marten.routes.reverse("accounts:transfers_show", token: raw_token)}"

      qr  = Goban::QR.encode_string(transfer_url)
      svg = Goban::SVGExporter.svg_string(qr, 4)

      response = respond(svg, content_type: "image/svg+xml", status: 200)
      response.headers["Cache-Control"] = "public, max-age=31536000"
      response
    end
  end
end

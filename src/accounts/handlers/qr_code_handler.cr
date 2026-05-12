module Accounts
  # GET /qr/<code:str>
  # Generates and returns an SVG QR code that encodes the join URL for the
  # given join code.  No signed-link layer for now — we simply validate that
  # the code matches the current account's join_code before rendering.
  #
  # Cache: 1 year / public (the QR code changes only when the join code is
  # regenerated, at which point the URL path changes too).
  class QrCodeHandler < Marten::Handler
    def get
      code = params["code"].to_s
      account = Account.first!

      return head(:not_found) unless account.join_code == code

      join_url = "#{request.scheme}://#{request.host}#{Marten.routes.reverse("accounts:users_new", join_code: code)}"

      qr  = Goban::QR.encode_string(join_url)
      svg = Goban::SVGExporter.svg_string(qr, 4)

      response = respond(svg, content_type: "image/svg+xml", status: 200)
      response.headers["Cache-Control"] = "public, max-age=31536000"
      response
    end
  end
end

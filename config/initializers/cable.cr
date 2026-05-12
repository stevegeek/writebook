Cable.configure do |settings|
  # cable-cr's default for `route` looks up the wrong key in INTERNAL and
  # crashes on first read. Set it explicitly. (See workspace STATUS.md gotcha #9.)
  settings.route = "/cable"

  # Rename the auth-token query param so ActionCable JS's default `?token=...`
  # doesn't clash with our session-cookie-based connection auth.
  settings.token = "tok"
end

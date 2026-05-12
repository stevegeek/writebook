# Accounts app — singleton Account, per-user Access, project User extras
# (subclass of MartenAuth::User). Owns the auth UX flows: first_run,
# session new/create/destroy, users, profiles, transfers, join codes.
require "./concerns/**"
require "./models/**"
require "./schemas/**"
require "./handlers/**"
require "./template_context"
require "./routes"

module Accounts
  class App < Marten::App
    label "accounts"
  end
end

require "marten"
require "sqlite3"
require "marten_auth"
require "marten_turbo"
require "marten_cable"
require "marten_signed_id"
require "markd"
require "tartrazine"
require "vips"
require "goban"
require "goban/exporters/svg"

require "../config/settings/base"
require "../config/settings/**"
require "../config/initializers/**"

# App requirements. Apps must load before settings/initializers that
# reference their classes (e.g. auth.user_model = Accounts::User), but
# in Crystal's whole-program-compile world the order here is mostly for
# require-graph completeness — actual symbol resolution happens at type-
# check time after all files are loaded. Keep apps in dependency order
# anyway: accounts (User) before books (which references Accounts::User
# from the Accessable concern).
require "./accounts/app"
require "./books/app"

# `Accounts::FirstRunCreateHandler` calls `Books::SeedManualCommand` after
# the very first administrator is created. The CLI seeder lives under
# `books/cli/`, which is *not* loaded by `books/app.cr` (it's only required
# from `src/cli.cr` for `manage`), so pull it in explicitly so the web
# entrypoint sees the symbol. `marten/cli` defines the `Marten::CLI::Command`
# parent class the seeder inherits from.
require "marten/cli"
require "./books/cli/seed_manual"

# Project-cross-cutting template tags (translation popover used in both apps).
require "./translations"
require "./leafable_helpers"

# Project-level routes (mounts each app's routes module).
require "../config/routes"

# Cable wiring. Must come after apps + models load and before Marten.start.
require "./channels/**"
MartenCable.use(ApplicationCable::Connection)

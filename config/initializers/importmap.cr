# JS module importmap. Replaces what was previously a 27-line `<script
# type="importmap">` block inline in base.html.
#
# Vendor packages stay on jsdelivr CDNs for now (matches the prior setup);
# `marten importmap pin` can vendor them locally later. `keep_cdn_urls = true`
# preserves the literal CDN URLs in the rendered importmap rather than
# downloading + rewriting to `src/assets/vendor/`.
#
# Controllers + helpers live under `src/assets/javascript/`; `pin_all_from`
# with `to:` keeps the URL prefix (`/assets/javascript/...`) while exposing
# them under shorter module keys (`controllers/foo`, `helpers/bar`) — matches
# what every controller's `import ... from "helpers/..."` already references.
Marten.configure do |config|
  config.importmap.keep_cdn_urls = true

  config.importmap.draw do
    # Vendor packages.
    pin "@hotwired/turbo", "https://cdn.jsdelivr.net/npm/@hotwired/turbo@8.0.13/dist/turbo.es2017-esm.js"
    pin "@hotwired/stimulus", "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/dist/stimulus.js"
    pin "@rails/actioncable", "https://cdn.jsdelivr.net/npm/@rails/actioncable@8.0.0/+esm"
    pin "@rails/request.js", "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.11/+esm"
    # Basecamp's `house` markdown editor is not published to npm; vendor
    # the file locally (copied from writebook-rails' vendor/javascript).
    pin "house", "javascript/vendor/house.min.js"

    # Project actions — Turbo Stream custom actions that need to register
    # at boot time (via top-level side effects).
    pin "actions/scroll_into_view", "javascript/actions/scroll_into_view.js"

    # Helper modules — referenced by `import ... from "helpers/foo"` in
    # controllers (e.g. reading_progress_helpers, form_helpers).
    pin_all_from "src/assets/javascript/helpers", under: "helpers", to: "javascript/helpers"

    # Stimulus controllers — auto-discovered + loaded by application.js via
    # marten-stimulus's `eagerLoadControllersFrom("controllers", Stimulus)`.
    pin_all_from "src/assets/javascript/controllers", under: "controllers", to: "javascript/controllers"

    # Entrypoint loaded by `{% importmap %}` — boots Turbo + Stimulus and
    # eager-loads every `controllers/*_controller.js` discovered above.
    pin "application", "javascript/application.js"
  end
end

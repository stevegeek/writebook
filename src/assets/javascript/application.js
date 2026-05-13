// Application entrypoint loaded by {% importmap %} in base.html.
//
// Replaces what was previously ~30 lines of explicit
// `import FooController from "controllers/foo_controller"` +
// `Stimulus.register("foo", FooController)` calls inline in base.html.
// marten-stimulus's `eagerLoadControllersFrom` walks the importmap for
// every entry whose key starts with `controllers/`, imports it, and
// registers the default export under the dasherized controller name
// (`foo_controller.js` -> `data-controller="foo"`).
import * as Turbo from "@hotwired/turbo"
import { Application } from "@hotwired/stimulus"
import { eagerLoadControllersFrom } from "stimulus-loading"

// Turbo + Stimulus are exposed on `window` because a few hand-rolled
// JS bits (edit_mode_controller, custom turbo-stream actions) still
// reach for the globals. Once those are converted to ESM imports the
// window-attachments can drop.
window.Turbo = Turbo
const Stimulus = Application.start()
Stimulus.debug = false
window.Stimulus = Stimulus

// Boot the custom Turbo Stream actions (registered via top-level side
// effects on `Turbo.StreamActions`).
import "actions/scroll_into_view"

// Auto-discover and register every `controllers/*_controller.js` from
// the importmap.
eagerLoadControllersFrom("controllers", Stimulus)

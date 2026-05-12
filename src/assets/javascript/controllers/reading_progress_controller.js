import { Controller } from "@hotwired/stimulus"
import { getReadingProgress } from "helpers/reading_progress_helpers"

export default class extends Controller {
  static values = { bookId: Number }
  static classes = [ "lastRead" ]

  connect() {
    this.#markLastReadLeaf()
  }

  #markLastReadLeaf() {
    const [ leafId ] = getReadingProgress(this.bookIdValue)
    // ID matches `{% dom_id leaf %}` in _leaf.html — marten-turbo's namespaced
    // convention is `<app>_<model>_<pk>` (e.g. `books_leaf_42`).
    const leafElement = leafId && this.element.querySelector(`#books_leaf_${leafId}`)

    if (leafElement) {
      leafElement.classList.add(this.lastReadClass)
    }
  }
}

import { Controller } from "@hotwired/stimulus"

// The menu on a phone: it slides in over the page from a button, and goes away on the backdrop or on a click on a link. From md up it is
// always there and this does nothing (the classes that move it are only below md).
export default class extends Controller {
  static targets = ["panel", "backdrop"]

  open() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.backdropTarget.classList.remove("hidden")
  }

  close() {
    this.panelTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
  }
}

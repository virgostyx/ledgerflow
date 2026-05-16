import { Controller } from "@hotwired/stimulus"

// CSS hover handles display in most cases.
// This controller provides programmatic show/hide for keyboard/JS triggers.
export default class extends Controller {
  static targets = ["content"]

  show() {
    if (!this.hasContentTarget) return
    this.contentTarget.classList.remove("opacity-0", "invisible")
    this.contentTarget.classList.add("opacity-100", "visible")
  }

  hide() {
    if (!this.hasContentTarget) return
    this.contentTarget.classList.remove("opacity-100", "visible")
    this.contentTarget.classList.add("opacity-0", "invisible")
  }
}

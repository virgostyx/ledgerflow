import { Controller } from "@hotwired/stimulus"

// Generic show/hide disclosure toggle (e.g. an expandable table row).
export default class extends Controller {
  static targets = ["content", "icon"]

  toggle() {
    this.contentTarget.hidden = !this.contentTarget.hidden
    this.iconTarget.classList.toggle("rotate-90")
  }
}

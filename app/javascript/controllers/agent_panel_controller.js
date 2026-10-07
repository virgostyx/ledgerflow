import { Controller } from "@hotwired/stimulus"

// The assistant's side panel: opened by its tab or Ctrl+/ (Cmd+/), closed by Escape. Focus moves in on opening and back to the tab on closing.
export default class extends Controller {
  static targets = ["drawer", "button", "close"]

  toggle() { this.drawerTarget.hidden ? this.open() : this.close() }

  open() {
    if (!this.drawerTarget.hidden) return
    this.drawerTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    ;(this.drawerTarget.querySelector("textarea") || this.closeTarget).focus()
  }

  close() {
    this.drawerTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.buttonTarget.focus()
  }

  keydown(event) {
    if (event.key === "/" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      this.toggle()
    } else if (event.key === "Escape" && !this.drawerTarget.hidden) {
      this.close()
    }
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "chevron"]
  static values  = { open: Boolean }

  connect() {
    if (this.openValue) this._setOpen(true)
  }

  toggle() {
    this._setOpen(this.panelTarget.classList.contains("hidden"))
  }

  _setOpen(open) {
    if (open) {
      this.panelTarget.classList.remove("hidden")
      if (this.hasChevronTarget) this.chevronTarget.style.transform = "rotate(180deg)"
    } else {
      this.panelTarget.classList.add("hidden")
      if (this.hasChevronTarget) this.chevronTarget.style.transform = "rotate(0deg)"
    }
  }
}

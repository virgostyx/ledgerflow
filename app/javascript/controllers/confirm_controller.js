import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message", "confirmButton", "container"]

  confirmAction(event) {
    if (event) event.preventDefault()
    this.hide()
    if (window.confirmResolver) {
      window.confirmResolver(true)
      window.confirmResolver = null
    }
  }

  cancel(event) {
    if (event) event.preventDefault()
    this.hide()
    if (window.confirmResolver) {
      window.confirmResolver(false)
      window.confirmResolver = null
    }
  }

  show(message) {
    if (message && this.hasMessageTarget) {
      this.messageTarget.textContent = message
    }
    this.element.classList.remove("hidden")
    document.body.style.overflow = "hidden"
    setTimeout(() => {
      if (this.hasConfirmButtonTarget) this.confirmButtonTarget.focus()
    }, 100)
  }

  hide() {
    this.element.classList.add("hidden")
    document.body.style.overflow = ""
  }
}

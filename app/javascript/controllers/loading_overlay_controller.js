import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.showTimeout = null
    this.boundShow = this.show.bind(this)
    this.boundHide = this.hide.bind(this)

    document.addEventListener("turbo:submit-start", this.boundShow)
    document.addEventListener("turbo:load", this.boundHide)
    document.addEventListener("turbo:frame-load", this.boundHide)
    document.addEventListener("turbo:fetch-request-error", this.boundHide)
    this.boundSubmitEnd = this.submitEnd.bind(this)
    document.addEventListener("turbo:submit-end", this.boundSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("turbo:submit-start", this.boundShow)
    document.removeEventListener("turbo:load", this.boundHide)
    document.removeEventListener("turbo:frame-load", this.boundHide)
    document.removeEventListener("turbo:fetch-request-error", this.boundHide)
    document.removeEventListener("turbo:submit-end", this.boundSubmitEnd)
    clearTimeout(this.showTimeout)
  }

  // A form answered with a Turbo Stream changes the page in place: no page load follows to hide the overlay, so it is hidden when the answer is in (a redirect keeps it until the next page loads).
  submitEnd(event) {
    const type = event.detail?.fetchResponse?.response?.headers?.get("Content-Type") || ""
    if (type.includes("turbo-stream")) this.hide()
  }

  show() {
    clearTimeout(this.showTimeout)
    this.showTimeout = setTimeout(() => {
      this.element.classList.remove("hidden", "opacity-0", "pointer-events-none")
      this.element.classList.add("opacity-100")
    }, 300)
  }

  hide() {
    clearTimeout(this.showTimeout)
    this.element.classList.add("hidden", "opacity-0", "pointer-events-none")
    this.element.classList.remove("opacity-100")
  }
}

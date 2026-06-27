import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "lf_cookie_consent"

export default class extends Controller {
  connect() {
    if (!localStorage.getItem(STORAGE_KEY)) {
      requestAnimationFrame(() => this.element.classList.remove("translate-y-full"))
    }
  }

  accept() {
    localStorage.setItem(STORAGE_KEY, "accepted")
    this.#dismiss()
  }

  refuse() {
    localStorage.setItem(STORAGE_KEY, "refused")
    this.#dismiss()
  }

  #dismiss() {
    this.element.classList.add("translate-y-full")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
  }
}

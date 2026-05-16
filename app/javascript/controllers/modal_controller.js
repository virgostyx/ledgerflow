import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.addEventListener("modal:open", () => this.open())
    this.element.addEventListener("modal:close", () => this.close())
  }

  open() {
    this.element.classList.remove("hidden")
    document.body.style.overflow = "hidden"
    const firstField = this.element.querySelector("input:not([type='hidden']), textarea, select")
    if (firstField) firstField.focus()
  }

  close(event) {
    if (event) event.preventDefault()
    this.element.classList.add("hidden")
    document.body.style.overflow = ""
  }

  closeBackground(event) {
    if (event.target === event.currentTarget) this.close()
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "chevron"]

  connect() {
    this.isOpen = false
    this.outsideClickHandler = this.handleOutsideClick.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.outsideClickHandler)
  }

  toggle(event) {
    event.stopPropagation()
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    this.isOpen = true
    if (this.hasChevronTarget) this.chevronTarget.style.transform = "rotate(180deg)"
    setTimeout(() => document.addEventListener("click", this.outsideClickHandler), 0)
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.isOpen = false
    if (this.hasChevronTarget) this.chevronTarget.style.transform = ""
    document.removeEventListener("click", this.outsideClickHandler)
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}

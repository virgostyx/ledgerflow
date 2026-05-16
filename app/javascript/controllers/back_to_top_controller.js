import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.scrollHandler = this.onScroll.bind(this)
    window.addEventListener("scroll", this.scrollHandler, { passive: true })
    this.onScroll()
  }

  disconnect() {
    window.removeEventListener("scroll", this.scrollHandler)
  }

  onScroll() {
    if (window.scrollY > 300) {
      this.element.classList.remove("opacity-0", "pointer-events-none", "translate-y-4")
      this.element.classList.add("opacity-100", "translate-y-0")
    } else {
      this.element.classList.remove("opacity-100", "translate-y-0")
      this.element.classList.add("opacity-0", "pointer-events-none", "translate-y-4")
    }
  }

  scrollToTop() {
    window.scrollTo({ top: 0, behavior: "smooth" })
  }
}

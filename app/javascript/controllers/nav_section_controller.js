import { Controller } from "@hotwired/stimulus"

// A collapsible sidebar section (<details>). The open/closed choice is kept in localStorage so that it survives
// navigation; a section holding the current page stays open.
export default class extends Controller {
  static values = { key: String }

  connect() {
    const active = this.element.querySelector("a.bg-primary-100")
    if (!active && this.stored() === "closed") this.element.open = false
  }

  remember() {
    try { localStorage.setItem(this.storageKey, this.element.open ? "open" : "closed") } catch (_) { /* private mode */ }
  }

  stored() {
    try { return localStorage.getItem(this.storageKey) } catch (_) { return null }
  }

  get storageKey() { return `nav:${this.keyValue}` }
}

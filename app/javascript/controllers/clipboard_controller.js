import { Controller } from "@hotwired/stimulus"

// Copies the text of a draft to the clipboard and tells the server it was copied (A11), so that the use is counted. The text is the one in the box, as the person left it.
export default class extends Controller {
  static targets = [ "source" ]
  static values = { url: String }

  async copy(event) {
    const button = event.currentTarget
    const text = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(text)
      button.textContent = "Copied"
      const token = document.querySelector("meta[name='csrf-token']")?.content
      const body = new URLSearchParams({ text })
      await fetch(this.urlValue, { method: "POST", headers: { "X-CSRF-Token": token, "Content-Type": "application/x-www-form-urlencoded" }, body })
    } catch (_error) {
      this.sourceTarget.select()
      button.textContent = "Select and copy by hand"
    }
  }
}

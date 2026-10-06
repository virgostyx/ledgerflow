import { Controller } from "@hotwired/stimulus"

// The question box of a conversation: Enter sends, Shift+Enter breaks the line, the box is emptied once sent, and the list scrolls down as the answer is written.
export default class extends Controller {
  static targets = ["messages", "form", "input"]

  connect() {
    this.observer = new MutationObserver(() => this.scroll())
    this.observer.observe(this.messagesTarget, { childList: true, subtree: true, characterData: true })
    this.scroll()
  }

  disconnect() { this.observer.disconnect() }

  keydown(event) {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  reset(event) {
    if (event.detail.success) this.inputTarget.value = ""
  }

  scroll() { this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight }
}

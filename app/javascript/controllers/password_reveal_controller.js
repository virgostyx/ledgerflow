import { Controller } from "@hotwired/stimulus"

const MIN = 12 // guidance only: the server enforces the rule

// Sign-up password: Show/Hide and a live count towards the minimum length.
export default class extends Controller {
  static targets = ["input", "button", "hint"]

  toggle() {
    const reveal = this.inputTarget.type === "password"
    this.inputTarget.type = reveal ? "text" : "password"
    this.buttonTarget.textContent = reveal ? "Hide" : "Show"
    this.buttonTarget.setAttribute("aria-pressed", String(reveal))
  }

  count() {
    const n = this.inputTarget.value.length
    this.hintTarget.textContent =
      n === 0 ? `Minimum ${MIN} characters` :
      n < MIN ? `${n} of ${MIN} characters` :
      `✓ ${MIN} characters or more`
  }
}

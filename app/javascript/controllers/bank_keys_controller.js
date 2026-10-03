import { Controller } from "@hotwired/stimulus"

// Keyboard on the bank lines (F02): j / k move between lines, c confirms the suggestion, i ignores the line.
export default class extends Controller {
  static targets = ["row"]

  connect() {
    this.index = -1
    this.onKey = this.onKey.bind(this)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() { document.removeEventListener("keydown", this.onKey) }

  onKey(event) {
    if (event.metaKey || event.ctrlKey || event.altKey || event.target.matches("input, select, textarea")) return

    if (event.key === "j") this.move(1)
    else if (event.key === "k") this.move(-1)
    else if (event.key === "c") this.press("accept")
    else if (event.key === "i") this.press("ignore")
  }

  move(step) {
    if (this.rowTargets.length === 0) return
    this.index = Math.max(0, Math.min(this.rowTargets.length - 1, this.index + step))
    this.rowTargets.forEach((row, i) => row.classList.toggle("ring-2", i === this.index))
    this.rowTargets[this.index].classList.add("ring-primary-500")
    this.rowTargets[this.index].scrollIntoView({ block: "nearest" })
  }

  press(action) {
    const row = this.rowTargets[this.index]
    row?.querySelector(`form[data-bank-keys-action="${action}"] button, form[data-bank-keys-action="${action}"] input[type=submit]`)?.click()
  }
}

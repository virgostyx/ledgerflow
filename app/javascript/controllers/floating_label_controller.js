import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "label"]

  connect() {
    this.checkValue()
  }

  focus() {
    this.labelTarget.classList.add("floating-active")
    this.labelTarget.classList.remove("floating-inactive")
  }

  blur() {
    this.checkValue()
  }

  checkValue() {
    // A <select> always renders visible text in its box (the prompt option
    // included), unlike a text input which is blank when empty, so its label
    // must stay floated up rather than overlapping that text.
    const isSelect = this.inputTarget.tagName === "SELECT"
    const hasValue = isSelect || this.inputTarget.value.toString().trim() !== ""
    const isFocused = this.inputTarget === document.activeElement

    if (hasValue || isFocused) {
      this.labelTarget.classList.add("floating-active")
      this.labelTarget.classList.remove("floating-inactive")
    } else {
      this.labelTarget.classList.remove("floating-active")
      this.labelTarget.classList.add("floating-inactive")
    }
  }
}

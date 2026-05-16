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
    const hasValue = this.inputTarget.value.toString().trim() !== ""
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

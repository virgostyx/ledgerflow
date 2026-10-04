import { Controller } from "@hotwired/stimulus"

// Shows debit - credit of the ticked lines; the submit button is enabled only when the group balances,
// the allocate button as soon as the selection has both a debit and a credit line, the rounding button when the
// difference is not zero but within the entity's tolerance.
// Amounts are summed in cents to avoid float drift. The server re-validates.
// Keys (outside a field): j / k move between lines, x ticks the current one, n jumps to the next partner, l letters.
export default class extends Controller {
  static targets = ["box", "submit", "allocate", "rounding", "difference"]
  static values = { tolerance: { type: String, default: "0" } }

  connect() { this.current = 0; this.update(); this.focusCurrent() }

  update() {
    const ticked = this.boxTargets.filter(box => box.checked)
    const cents = ticked
      .reduce((sum, box) => sum + Math.round((parseFloat(box.dataset.debit) - parseFloat(box.dataset.credit)) * 100), 0)
    const selected = ticked.length

    this.differenceTarget.textContent = (cents / 100).toFixed(2)
    this.submitTarget.disabled = !(selected >= 2 && cents === 0)
    this.allocateTarget.disabled = !(ticked.some(box => parseFloat(box.dataset.debit) > 0) && ticked.some(box => parseFloat(box.dataset.credit) > 0))
    if (this.hasRoundingTarget) {
      this.roundingTarget.disabled = !(selected >= 2 && cents !== 0 && Math.abs(cents) <= Math.round(parseFloat(this.toleranceValue) * 100))
    }
  }

  key(event) {
    if (event.target.closest("input[type=text], input[type=number], textarea, select") || event.ctrlKey || event.metaKey || event.altKey) return
    const boxes = this.boxTargets
    if (boxes.length === 0) return

    switch (event.key) {
      case "j": this.current = Math.min(this.current + 1, boxes.length - 1); break
      case "k": this.current = Math.max(this.current - 1, 0); break
      case "x": boxes[this.current].checked = !boxes[this.current].checked; this.update(); break
      case "n": this.current = this.nextPartnerIndex(); break
      case "l": if (!this.submitTarget.disabled) this.submitTarget.click(); return
      default: return
    }
    event.preventDefault()
    this.focusCurrent()
  }

  nextPartnerIndex() {
    const boxes = this.boxTargets
    const partner = boxes[this.current].dataset.partner
    const next = boxes.findIndex((box, i) => i > this.current && box.dataset.partner !== partner)
    return next === -1 ? this.current : next
  }

  focusCurrent() {
    const box = this.boxTargets[this.current]
    if (box) box.focus({ preventScroll: false })
  }
}

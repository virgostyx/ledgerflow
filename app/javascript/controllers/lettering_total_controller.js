import { Controller } from "@hotwired/stimulus"

// Shows debit - credit of the ticked lines; the submit button is enabled only when the group balances,
// the allocate button as soon as the selection has both a debit and a credit line.
// Amounts are summed in cents to avoid float drift. The server re-validates.
export default class extends Controller {
  static targets = ["box", "submit", "allocate", "difference"]

  connect() { this.update() }

  update() {
    const ticked = this.boxTargets.filter(box => box.checked)
    const cents = ticked
      .reduce((sum, box) => sum + Math.round((parseFloat(box.dataset.debit) - parseFloat(box.dataset.credit)) * 100), 0)
    const selected = ticked.length

    this.differenceTarget.textContent = (cents / 100).toFixed(2)
    this.submitTarget.disabled = !(selected >= 2 && cents === 0)
    this.allocateTarget.disabled = !(ticked.some(box => parseFloat(box.dataset.debit) > 0) && ticked.some(box => parseFloat(box.dataset.credit) > 0))
  }
}

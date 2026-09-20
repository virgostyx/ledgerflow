import { Controller } from "@hotwired/stimulus"

// Shows debit - credit of the ticked lines; the submit button is enabled only when the group balances.
// Amounts are summed in cents to avoid float drift. The server re-validates.
export default class extends Controller {
  static targets = ["box", "submit", "difference"]

  connect() { this.update() }

  update() {
    const cents = this.boxTargets
      .filter(box => box.checked)
      .reduce((sum, box) => sum + Math.round((parseFloat(box.dataset.debit) - parseFloat(box.dataset.credit)) * 100), 0)
    const selected = this.boxTargets.filter(box => box.checked).length

    this.differenceTarget.textContent = (cents / 100).toFixed(2)
    this.submitTarget.disabled = !(selected >= 2 && cents === 0)
  }
}

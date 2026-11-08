import { Controller } from "@hotwired/stimulus"

// Landing-page demo: an invoice (sale or purchase) becomes a balanced PCMN journal entry, live.
// Integer cents only (no float money); VAT rounded half-up.
export default class extends Controller {
  static targets = ["net", "sale", "purchase", "netCell", "vatCell", "grossCell", "status", "label"]

  connect() { this.update() }

  update() {
    const checked = (n) => this.element.querySelector(`input[name=${n}]:checked`).value
    const purchase = checked("kind") === "purchase"
    const net = Math.max(0, Math.round((parseFloat(this.netTarget.value) || 0) * 100))
    const vat = Math.round((net * parseInt(checked("rate"), 10)) / 100)
    const gross = net + vat
    const fmt = (c) => (c / 100).toLocaleString("fr-BE", { style: "currency", currency: "EUR" })

    this.saleTarget.hidden = purchase
    this.purchaseTarget.hidden = !purchase
    this.labelTarget.textContent = purchase ? "Purchase excl. VAT (€)" : "Sale excl. VAT (€)"
    this.netCellTargets.forEach((e) => (e.textContent = fmt(net)))
    this.vatCellTargets.forEach((e) => (e.textContent = fmt(vat)))
    this.grossCellTargets.forEach((e) => (e.textContent = fmt(gross)))
    this.statusTarget.textContent = `Debit ${fmt(gross)} = Credit ${fmt(gross)} ✓ balanced`
  }
}

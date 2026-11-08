import { Controller } from "@hotwired/stimulus"

// Landing-page demo: a sales invoice becomes a balanced PCMN journal entry, live.
// Integer cents only (no float money); VAT rounded half-up.
export default class extends Controller {
  static targets = ["net", "debit", "credit", "vat", "total", "status"]

  connect() { this.update() }

  update() {
    const net = Math.max(0, Math.round((parseFloat(this.netTarget.value) || 0) * 100))
    const rate = parseInt(this.element.querySelector("input[name=rate]:checked").value, 10)
    const vat = Math.round((net * rate) / 100)
    const total = net + vat
    const fmt = (c) => (c / 100).toLocaleString("fr-BE", { style: "currency", currency: "EUR" })

    this.debitTarget.textContent = fmt(total)
    this.totalTarget.textContent = fmt(total)
    this.creditTarget.textContent = fmt(net)
    this.vatTarget.textContent = fmt(vat)
    this.statusTarget.textContent = `Debit ${fmt(total)} = Credit ${fmt(net + vat)} ✓ balanced`
  }
}

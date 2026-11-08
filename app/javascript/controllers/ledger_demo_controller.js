import { Controller } from "@hotwired/stimulus"

// Landing-page demo: an invoice (sale or purchase) becomes a balanced PCMN journal entry, live.
// Integer cents only (no float money); VAT rounded half-up.
export default class extends Controller {
  static targets = ["net", "sale", "purchase", "netCell", "vatCell", "grossCell", "status", "label", "breakBtn"]

  connect() { this.broken = false; this.update() }

  toggleBreak() { this.broken = !this.broken; this.update() }

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
    this.netCellTargets.forEach((e) => this.set(e, fmt(net)))
    this.vatCellTargets.forEach((e) => this.set(e, fmt(vat)))
    this.grossCellTargets.forEach((e) => this.set(e, fmt(gross)))
    // Broken: credit side short by 1 €, as a typo would leave it.
    const credit = this.broken ? Math.max(0, gross - 100) : gross
    const ok = credit === gross
    this.breakBtnTarget.textContent = this.broken ? "Fix it" : "Try to break it"
    this.statusTarget.className = `mt-4 text-sm font-medium ${ok ? "text-green-700" : "text-red-700"}`
    this.statusTarget.textContent = ok
      ? `Debit ${fmt(gross)} = Credit ${fmt(credit)} ✓ balanced`
      : `✗ Rejected by PostgreSQL: debit ${fmt(gross)} ≠ credit ${fmt(credit)}. Nothing was saved.`
  }

  // Set text; flash the cell only if its value changed (skipped for reduced motion).
  set(el, text) {
    if (el.textContent.replace(/\s/g, " ") === text.replace(/\s/g, " ")) return  // server-rendered default
    const first = el.textContent === ""
    el.textContent = text
    if (first || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    el.animate([{ backgroundColor: "#fed7aa" }, { backgroundColor: "transparent" }], { duration: 700 })
  }
}

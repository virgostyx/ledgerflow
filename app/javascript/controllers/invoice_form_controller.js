import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    // Header fields (existing)
    "invoiceDate", "dueDate", "journalSelect", "entryNumberPreview",
    // Lines management
    "linesContainer", "lineTemplate", "lineRow",
    // Per-line computed display (readonly)
    "lineVat", "lineTotal",
    // Invoice-level totals display
    "invoiceSubtotal", "invoiceVat", "invoiceTotal"
  ]
  static values = {
    days:  { type: Number, default: 0 },
    axes:  { type: Array,  default: [] }
  }

  // ------------------------------------------------------------------
  // Existing: due date auto-fill
  // ------------------------------------------------------------------

  fillDueDate() {
    if (this.dueDateTarget.value) return

    const raw = this.invoiceDateTarget.value
    if (!raw) return

    const [year, month, day] = raw.split("-").map(Number)
    if (!year || !month || !day || year < 1000) return

    const date = new Date(0)
    date.setFullYear(year, month - 1, day)
    date.setDate(date.getDate() + this.daysValue)

    const yyyy = date.getFullYear()
    const mm   = String(date.getMonth() + 1).padStart(2, "0")
    const dd   = String(date.getDate()).padStart(2, "0")
    this.dueDateTarget.value = `${yyyy}-${mm}-${dd}`

    this.dueDateTarget.dispatchEvent(new Event("change"))
  }

  updateEntryNumber() {
    if (!this.hasEntryNumberPreviewTarget) return
    const select = this.journalSelectTarget
    const option = select.options[select.selectedIndex]
    this.entryNumberPreviewTarget.value = option?.dataset.nextNumber ?? ""
  }

  // ------------------------------------------------------------------
  // Lines management
  // ------------------------------------------------------------------

  addLine() {
    const template = this.lineTemplateTarget.content.cloneNode(true)
    const newIndex = this.linesContainerTarget.querySelectorAll(".invoice-line-row").length

    template.querySelectorAll("[name]").forEach(el => {
      el.name = el.name.replace(/NEW_INDEX/g, newIndex)
    })
    template.querySelectorAll("[id]").forEach(el => {
      el.id = el.id.replace(/NEW_INDEX/g, newIndex)
    })
    template.querySelectorAll("[for]").forEach(el => {
      el.htmlFor = el.htmlFor.replace(/NEW_INDEX/g, newIndex)
    })

    this.linesContainerTarget.appendChild(template)
    this.computeInvoiceTotals()
  }

  removeLine(event) {
    const row = event.target.closest(".invoice-line-row")
    if (!row) return

    const destroyInput = row.querySelector("[name$='[_destroy]']")
    if (destroyInput) {
      destroyInput.value = "1"
      row.style.display = "none"
    } else {
      row.remove()
    }
    this.computeInvoiceTotals()
  }

  // ------------------------------------------------------------------
  // Totals computation
  // ------------------------------------------------------------------

  computeLineTotals(event) {
    const row = event.target.closest(".invoice-line-row")
    if (!row) return

    const amount = parseFloat(row.querySelector("[data-line-amount]")?.value) || 0
    const rate   = parseFloat(row.querySelector("[data-line-vat-rate]")?.value) || 0

    const vat   = Math.round(amount * rate / 100 * 100) / 100
    const total = Math.round((amount + vat) * 100) / 100

    const fmt = (n) => n.toLocaleString("fr-BE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })

    const vatEl   = row.querySelector("[data-line-vat-display]")
    const totalEl = row.querySelector("[data-line-total-display]")

    if (vatEl)   vatEl.textContent   = fmt(vat)
    if (totalEl) totalEl.textContent = fmt(total)

    this.computeInvoiceTotals()
  }

  computeInvoiceTotals() {
    let totalSubtotal = 0
    let totalVat      = 0
    let totalTotal    = 0

    this.linesContainerTarget.querySelectorAll(".invoice-line-row").forEach(row => {
      if (row.style.display === "none") return

      const amount = parseFloat(row.querySelector("[data-line-amount]")?.value) || 0
      const rate   = parseFloat(row.querySelector("[data-line-vat-rate]")?.value) || 0

      const vat = Math.round(amount * rate / 100 * 100) / 100

      totalSubtotal += amount
      totalVat      += vat
      totalTotal    += amount + vat
    })

    const fmt = (n) => n.toLocaleString("fr-BE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })

    if (this.hasInvoiceSubtotalTarget) this.invoiceSubtotalTarget.textContent = fmt(totalSubtotal)
    if (this.hasInvoiceVatTarget)      this.invoiceVatTarget.textContent      = fmt(totalVat)
    if (this.hasInvoiceTotalTarget)    this.invoiceTotalTarget.textContent    = fmt(totalTotal)
  }

  // ------------------------------------------------------------------
  // Analytical axes — same pattern as journal_entry_form_controller
  // ------------------------------------------------------------------

  onAccountSelected(event) {
    const row = event.target.closest(".invoice-line-row")
    if (!row || !this.hasAxesValue || this.axesValue.length === 0) return

    const accountId = event.detail?.accountId
    if (!accountId) return

    const accountsEl = event.target.closest("[data-account-search-accounts-value]")
    if (!accountsEl) return

    const accounts = JSON.parse(accountsEl.dataset.accountSearchAccountsValue || "[]")
    const account  = accounts.find(a => String(a.id) === String(accountId))
    if (!account) return

    const accountClass = account.account_class
    this.axesValue.forEach(axis => {
      const required  = axis.required_for.includes(accountClass)
      const axisField = row.querySelector(`.axis-field[data-axis-code="${axis.code}"]`)
      if (!axisField) return

      const marker = axisField.querySelector(".required-marker")
      const label  = axisField.querySelector(".axis-label")
      if (marker) marker.classList.toggle("hidden", !required)
      if (label)  label.classList.toggle("text-red-500", required)
      if (label)  label.classList.toggle("text-gray-400", !required)
    })
  }

  onAxisAccountChanged(event) {
    const select    = event.target
    const axisBlock = select.closest(".axis-field")
    if (!axisBlock) return

    const destroyField = axisBlock.querySelector("[data-destroy-field]")
    const idField      = axisBlock.querySelector("[name$='[id]']")
    if (!destroyField) return

    const hasExistingRecord = idField && idField.value !== ""
    const isClearing        = select.value === ""
    destroyField.value = (hasExistingRecord && isClearing) ? "1" : "0"
  }
}

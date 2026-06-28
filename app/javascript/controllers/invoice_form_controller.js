import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["invoiceDate", "dueDate", "journalSelect", "entryNumberPreview"]
  static values  = { days: { type: Number, default: 0 } }

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
    const select  = this.journalSelectTarget
    const option  = select.options[select.selectedIndex]
    this.entryNumberPreviewTarget.value = option?.dataset.nextNumber ?? ""
  }
}

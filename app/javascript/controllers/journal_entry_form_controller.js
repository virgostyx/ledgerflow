import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["linesContainer", "lineTemplate", "debitInput", "creditInput",
                    "balanceIndicator", "submitButton", "line"]
  static values  = { axes: Array, rateLookupUrl: String }

  connect() {
    this.computeBalance()
  }

  addLine() {
    const template = this.lineTemplateTarget.content.cloneNode(true)
    const newIndex = this.linesContainerTarget.querySelectorAll(".entry-lines").length

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
    this.computeBalance()
  }

  removeLine(event) {
    const line = event.target.closest(".entry-lines")
    if (line) {
      const destroyInput = line.querySelector("[name$='[_destroy]']:not([data-destroy-field])")
      if (destroyInput) {
        destroyInput.value = "1"
        line.style.display = "none"
      } else {
        line.remove()
      }
      this.computeBalance()
    }
  }

  // A line in a foreign currency (F11): the amount in that currency, at the official rate of the entry date, becomes the euros of the debit or the credit.
  // The rate is shown, never typed here; a missing rate says which, and nothing is guessed.
  async onForeignChanged(event) {
    const line = event.target.closest(".entry-lines")
    if (!line) return
    const field = (name) => line.querySelector(`[name$="[${name}]"]`)
    const notice = line.querySelector("[data-journal-entry-form-target='foreignNotice']")
    const code = field("currency").value
    const debit = field("debit"), credit = field("credit"), rate = field("exchange_rate")
    notice.textContent = ""
    if (code === "EUR") { rate.value = ""; return }

    const amount = parseFloat(field("amount_currency").value)
    const date = this.element.querySelector("[name$='[entry_date]']")?.value
    if (!date || !this.rateLookupUrlValue) return
    const response = await fetch(`${this.rateLookupUrlValue}?currency=${encodeURIComponent(code)}&date=${encodeURIComponent(date)}`, { headers: { Accept: "application/json" } })
    const data = await response.json()
    if (!response.ok) { rate.value = ""; notice.textContent = data.error || "No rate"; return }

    rate.value = data.rate
    if (!(amount > 0)) return
    const eur = Math.round(amount / parseFloat(data.rate) * 100) / 100
    const side = field("side").value
    ;(side === "credit" ? credit : debit).value = eur
    ;(side === "credit" ? debit : credit).value = 0
    notice.textContent = `${eur.toFixed(2)} EUR at ${data.rate}`
    this.computeBalance()
  }

  // Called when an account is selected in a line (via account-search:selected custom event)
  onAccountSelected(event) {
    const line = event.target.closest(".entry-lines")
    if (!line || !this.hasAxesValue) return

    const accountId = event.detail?.accountId
    if (!accountId) return

    const axesData   = this.axesValue
    const accountsEl = event.target.closest("[data-account-search-accounts-value]")
    if (!accountsEl) return

    const accounts = JSON.parse(accountsEl.dataset.accountSearchAccountsValue || "[]")
    const account  = accounts.find(a => String(a.id) === String(accountId))
    if (!account) return

    const accountClass = account.account_class
    axesData.forEach(axis => {
      const required = axis.required_for.includes(accountClass)
      const axisField = line.querySelector(`.axis-field[data-axis-code="${axis.code}"]`)
      if (!axisField) return

      const marker = axisField.querySelector(".required-marker")
      const label  = axisField.querySelector(".axis-label")
      if (marker) marker.classList.toggle("hidden", !required)
      if (label)  label.classList.toggle("text-red-500", required)
      if (label)  label.classList.toggle("text-gray-400", !required)
    })
  }

  // Called when an axis account select changes — manages _destroy field for existing annotations
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

  computeBalance() {
    let totalDebit  = 0
    let totalCredit = 0

    this.debitInputTargets.forEach(input => {
      const val = parseFloat(input.value) || 0
      totalDebit += val
    })
    this.creditInputTargets.forEach(input => {
      const val = parseFloat(input.value) || 0
      totalCredit += val
    })

    const diff      = Math.abs(totalDebit - totalCredit)
    const balanced  = diff < 0.01 && (totalDebit > 0 || totalCredit > 0)
    const hasValues = totalDebit > 0 || totalCredit > 0

    this.updateBalanceIndicator(balanced, hasValues, diff)
    this.updateSubmitButton(balanced)
  }

  updateBalanceIndicator(balanced, hasValues, diff) {
    const indicator = this.balanceIndicatorTarget

    if (!hasValues) {
      indicator.innerHTML = '<span class="bg-gray-100 text-gray-600 text-xs font-medium px-2 py-1 rounded-full">Pending</span>'
      return
    }

    if (balanced) {
      indicator.innerHTML = '<span class="bg-emerald-100 text-emerald-700 text-xs font-medium px-2 py-1 rounded-full">Balanced</span>'
    } else {
      const formatted = diff.toLocaleString("en-BE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
      indicator.innerHTML = `<span class="bg-red-100 text-red-700 text-xs font-medium px-2 py-1 rounded-full">Unbalanced (${formatted})</span>`
    }
  }

  updateSubmitButton(balanced) {
    this.submitButtonTargets.forEach(btn => {
      btn.disabled = !balanced
    })
  }
}

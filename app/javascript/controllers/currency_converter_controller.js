import { Controller } from "@hotwired/stimulus"

// Static ECB reference rates (EUR base — units of foreign currency per 1 EUR)
const RATES = {
  USD: 1.0850,
  GBP: 0.8580,
  CHF: 0.9680,
  JPY: 163.50,
}

export default class extends Controller {
  static targets = [
    "panel", "currencySelect", "amountInput", "resultDisplay",
    "directionFromLabel", "directionToLabel", "rateInfo", "copyText",
  ]

  connect() {
    this.toEur = true  // true = foreign → EUR, false = EUR → foreign
    this.currentResult = null
    this.keydownHandler = this.handleKeydown.bind(this)
    this.outsideClickHandler = this.handleOutsideClick.bind(this)
    this._updateDirectionLabels()
  }

  disconnect() {
    document.removeEventListener("keydown", this.keydownHandler)
    document.removeEventListener("click", this.outsideClickHandler)
  }

  handleKeydown(event) {
    if (event.key === "Escape") { event.preventDefault(); this.close() }
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  // ── Panel ──────────────────────────────────────────────────────────────────

  toggle() {
    this.panelTarget.classList.contains("hidden") ? this.open() : this.close()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    document.addEventListener("keydown", this.keydownHandler)
    setTimeout(() => document.addEventListener("click", this.outsideClickHandler), 0)
    if (this.hasAmountInputTarget) this.amountInputTarget.focus()
  }

  close() {
    this.panelTarget.classList.add("hidden")
    document.removeEventListener("keydown", this.keydownHandler)
    document.removeEventListener("click", this.outsideClickHandler)
  }

  // ── Events ─────────────────────────────────────────────────────────────────

  currencyChanged() {
    this._updateDirectionLabels()
    this.convert()
  }

  swapDirection() {
    this.toEur = !this.toEur
    this._updateDirectionLabels()
    this.convert()
  }

  convert() {
    const currency = this.currencySelectTarget.value
    const rate = RATES[currency]
    if (!rate) return

    const raw = this.amountInputTarget.value.replace(",", ".")
    const amount = parseFloat(raw)

    if (isNaN(amount) || amount < 0) {
      this.resultDisplayTarget.textContent = "—"
      this.currentResult = null
      return
    }

    // toEur:  foreign → EUR  = amount / rate
    // !toEur: EUR → foreign  = amount * rate
    this.currentResult = this.toEur ? amount / rate : amount * rate

    this.resultDisplayTarget.textContent = new Intl.NumberFormat("en-BE", {
      minimumFractionDigits: 2,
      maximumFractionDigits: currency === "JPY" ? 0 : 2,
    }).format(this.currentResult)

    const eurPerUnit = 1 / rate
    const rateStr = this.toEur
      ? `1 ${currency} = ${eurPerUnit.toFixed(4)} EUR`
      : `1 EUR = ${rate.toFixed(4)} ${currency}`
    this.rateInfoTarget.textContent = rateStr
  }

  // ── Clipboard ──────────────────────────────────────────────────────────────

  async copy() {
    if (this.currentResult === null) return

    const text = this.currentResult.toFixed(2)
    const setText = (t) => { if (this.hasCopyTextTarget) this.copyTextTarget.textContent = t }

    try {
      await navigator.clipboard.writeText(text)
    } catch {
      const input = document.createElement("input")
      input.value = text
      document.body.appendChild(input)
      input.select()
      document.execCommand("copy")
      document.body.removeChild(input)
    }

    setText("✓ Copied!")
    setTimeout(() => setText("Copy result"), 2000)
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  _updateDirectionLabels() {
    const currency = this.currencySelectTarget.value
    if (this.hasDirectionFromLabelTarget) {
      this.directionFromLabelTarget.textContent = this.toEur ? currency : "EUR"
    }
    if (this.hasDirectionToLabelTarget) {
      this.directionToLabelTarget.textContent = this.toEur ? "EUR" : currency
    }
  }
}

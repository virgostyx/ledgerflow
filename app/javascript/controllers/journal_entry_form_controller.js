import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["linesContainer", "lineTemplate", "debitInput", "creditInput",
                    "balanceIndicator", "balanceAnnouncer", "undoNotice", "cancelLink", "submitButton", "line", "totalDebit", "totalCredit"]
  static values  = { axes: Array, rateLookupUrl: String, undoDelay: { type: Number, default: 8000 } }

  connect() {
    this.computeBalance()
    // After a refused save, the summary of what went wrong takes the focus (and is read out).
    this.element.querySelector("[data-entry-errors]")?.focus()
  }

  markDirty() {
    this.dirty = true
  }

  // Cancel leaves a clean form at once. After typing, the first click asks, naming what is lost; the second one leaves.
  cancel(event) {
    if (!this.dirty || this.confirmingCancel) return
    event.preventDefault()
    const link = this.cancelLinkTarget
    this.confirmingCancel = true
    this.cancelLabel = link.textContent
    link.textContent = link.dataset.discardLabel
    link.classList.add("font-medium", "text-red-700")
    this.cancelTimer = setTimeout(() => {
      this.confirmingCancel = false
      link.textContent = this.cancelLabel
      link.classList.remove("font-medium", "text-red-700")
    }, 5000)
  }

  addLine() {
    const template = this.lineTemplateTarget.content.cloneNode(true)
    // Never reuse an index: removing a middle line and adding another must not overwrite a line.
    this.nextIndex = Math.max(this.nextIndex || 0, this.linesContainerTarget.querySelectorAll(".entry-lines").length)
    const newIndex = this.nextIndex++

    template.querySelectorAll("[name]").forEach(el => {
      el.name = el.name.replace(/NEW_INDEX/g, newIndex)
    })
    template.querySelectorAll("[id]").forEach(el => {
      el.id = el.id.replace(/NEW_INDEX/g, newIndex)
    })
    template.querySelectorAll("[for]").forEach(el => {
      el.htmlFor = el.htmlFor.replace(/NEW_INDEX/g, newIndex)
    })

    this.dirty = true
    this.linesContainerTarget.appendChild(template)
    const line = this.linesContainerTarget.lastElementChild

    // The new line starts with the amount still missing on the side that lacks it, and takes the focus.
    const debit  = this.sumCents(this.debitInputTargets)
    const credit = this.sumCents(this.creditInputTargets)
    if (debit !== credit) {
      const missing = Math.abs(debit - credit)
      const side = debit > credit ? "credit" : "debit"
      const input = line.querySelector(`[name$="[${side}]"]`)
      if (input) input.value = (missing / 100).toFixed(2)
    }
    this.computeBalance()
    this.focusAccount(line)
  }

  // Moving the focus by code must not pop the account list open over what the person is looking at (the Undo notice, the next line).
  focusAccount(line) {
    const input = line?.querySelector("input[data-account-search-target='input']")
    if (!input) return
    input.dataset.suppressOpen = "1"
    input.focus()
  }

  // Tabbing or clicking into an amount selects it, so typing replaces the 0.00 instead of extending it.
  selectAll(event) {
    event.target.select()
  }

  // Ctrl+Enter (Cmd+Enter on a Mac) adds a line from anywhere in the form; plain Enter is left to the field.
  shortcut(event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      this.addLine()
    }
  }

  // Removing a line is undoable for a few seconds. A saved line is only hidden and flagged _destroy; a new line is hidden and its fields
  // disabled (so it is not submitted) and dropped from the page once the undo window has passed.
  removeLine(event) {
    const line = event.target.closest(".entry-lines")
    if (!line) return
    this.commitRemoval()
    this.dirty = true

    const visible = this.visibleLines()
    const index = visible.indexOf(line)
    const destroyInput = line.querySelector("[name$='[_destroy]']:not([data-destroy-field])")
    if (destroyInput) {
      destroyInput.value = "1"
    } else {
      line.querySelectorAll("input, select, button").forEach(el => { el.disabled = true })
    }
    line.style.display = "none"
    this.computeBalance()

    const neighbour = visible[index + 1] || visible[index - 1]
    this.focusAccount(neighbour)

    this.pendingRemoval = { line, destroyInput, timer: setTimeout(() => this.commitRemoval(), this.undoDelayValue) }
    this.undoNoticeTarget.hidden = false
  }

  undoRemove() {
    const pending = this.pendingRemoval
    if (!pending) return
    clearTimeout(pending.timer)
    if (pending.destroyInput) {
      pending.destroyInput.value = "0"
    } else {
      pending.line.querySelectorAll("input, select, button").forEach(el => { el.disabled = false })
    }
    pending.line.style.display = ""
    this.pendingRemoval = null
    this.undoNoticeTarget.hidden = true
    this.computeBalance()
    this.focusAccount(pending.line)
  }

  commitRemoval() {
    const pending = this.pendingRemoval
    if (!pending) return
    clearTimeout(pending.timer)
    if (!pending.destroyInput) pending.line.remove()
    this.pendingRemoval = null
    this.undoNoticeTarget.hidden = true
    this.computeBalance()
  }

  visibleLines() {
    return this.lineTargets.filter(line => line.style.display !== "none")
  }

  // Typing an amount on one side clears the other: a line is a debit or a credit, never both.
  onAmountInput(event) {
    const input = event.target
    if ((parseFloat(input.value) || 0) > 0) {
      const otherSide = input.name.endsWith("[debit]") ? "credit" : "debit"
      const other = input.closest(".entry-lines")?.querySelector(`[name$="[${otherSide}]"]`)
      if (other && (parseFloat(other.value) || 0) !== 0) other.value = "0.00"
    }
    this.computeBalance()
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
    this.setNotice(notice, "")
    if (code === "EUR") { rate.value = ""; return }

    const amount = parseFloat(field("amount_currency").value)
    const date = this.element.querySelector("[name$='[entry_date]']")?.value
    if (!date || !this.rateLookupUrlValue) return
    let response, data
    try {
      response = await fetch(`${this.rateLookupUrlValue}?currency=${encodeURIComponent(code)}&date=${encodeURIComponent(date)}`, { headers: { Accept: "application/json" } })
      data = await response.json()
    } catch {
      // Offline or an unreadable answer: say so, and never keep a rate that no longer matches the currency.
      rate.value = ""
      this.setNotice(notice, "Could not fetch the exchange rate. Check your connection, then change the amount to try again.", true)
      return
    }
    if (!response.ok) { rate.value = ""; this.setNotice(notice, data.error || "No rate", true); return }

    rate.value = data.rate
    if (!(amount > 0)) return
    const eur = Math.round(amount / parseFloat(data.rate) * 100) / 100
    const side = field("side").value
    ;(side === "credit" ? credit : debit).value = eur
    ;(side === "credit" ? debit : credit).value = 0
    this.setNotice(notice, `${eur.toFixed(2)} EUR at ${data.rate}`)
    this.computeBalance()
  }

  // A converted amount is information (neutral); a missing rate or a failed lookup is a problem (red).
  setNotice(notice, text, isError = false) {
    notice.textContent = text
    notice.classList.toggle("text-red-700", isError)
    notice.classList.toggle("text-gray-600", !isError)
  }

  // Called when an account is selected in a line (via account-search:selected custom event)
  onAccountSelected(event) {
    this.computeBalance()
    const line = event.target.closest(".entry-lines")
    if (!line || !this.hasAxesValue) return

    const accountId = event.detail?.accountId
    if (!accountId) return

    const axesData   = this.axesValue
    const account = this.accountsById().get(String(accountId))
    if (!account) return

    const accountClass = account.account_class
    let anyRequired = false
    axesData.forEach(axis => {
      const required = axis.required_for.includes(accountClass)
      anyRequired = anyRequired || required
      const axisField = line.querySelector(`.axis-field[data-axis-code="${axis.code}"]`)
      if (!axisField) return

      const marker = axisField.querySelector(".required-marker")
      const label  = axisField.querySelector(".axis-label")
      if (marker) marker.classList.toggle("hidden", !required)
      if (label)  label.classList.toggle("text-red-700", required)
      if (label)  label.classList.toggle("text-gray-600", !required)
    })

    // The analytics are folded away on a plain line; a required axis must not stay out of sight.
    line.querySelector("[data-line-extras-required]")?.classList.toggle("hidden", !anyRequired)
    if (anyRequired) line.querySelector("details.line-extras")?.setAttribute("open", "")
  }

  // Called when an axis account select changes — manages _destroy field for existing annotations
  onAxisAccountChanged(event) {
    this.computeBalance()
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

  // Sum in whole cents so the comparison never depends on float rounding. A line the user removed (a saved line is only hidden, flagged _destroy) does not count.
  sumCents(inputs) {
    return inputs
      .filter(input => input.closest(".entry-lines")?.style.display !== "none")
      .reduce((sum, input) => sum + Math.round((parseFloat(input.value) || 0) * 100), 0)
  }

  formatCents(cents) {
    return (cents / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }

  // What stops a line from being saved even when debit equals credit: no account, or an analytic account that its account requires.
  lineIssues() {
    const accounts = this.accountsById()
    const issues = { needAccount: 0, needAnalytic: 0 }
    this.visibleLines().forEach(line => {
      const cents = (name) => Math.round((parseFloat(line.querySelector(`[name$="[${name}]"]`)?.value) || 0) * 100)
      if (cents("debit") === 0 && cents("credit") === 0) return
      const accountId = line.querySelector("[name$='[account_id]']")?.value
      if (!accountId) { issues.needAccount++; return }
      const accountClass = accounts.get(String(accountId))?.account_class
      const missing = this.axesValue.some(axis => {
        if (!axis.required_for.includes(accountClass)) return false
        const select = line.querySelector(`.axis-field[data-axis-code="${axis.code}"] select`)
        return select && select.value === ""
      })
      if (missing) issues.needAnalytic++
    })
    return issues
  }

  accountsById() {
    if (!this.accounts) {
      const script = document.getElementById("journal-entry-accounts")
      const list = JSON.parse(script?.textContent || "[]")
      this.accounts = new Map(list.map(a => [String(a.id), a]))
    }
    return this.accounts
  }

  computeBalance() {
    const debit  = this.sumCents(this.debitInputTargets)
    const credit = this.sumCents(this.creditInputTargets)
    const diff   = Math.abs(debit - credit)
    const hasValues = debit > 0 || credit > 0
    const balanced  = diff === 0 && hasValues
    const issues = this.lineIssues()
    const blocked = issues.needAccount + issues.needAnalytic > 0

    this.totalDebitTarget.textContent  = this.formatCents(debit)
    this.totalCreditTarget.textContent = this.formatCents(credit)
    this.updateBalanceIndicator(balanced, hasValues, debit, credit, issues)
    this.updateSubmitButton(balanced && !blocked)
  }

  issueSentence(issues) {
    const lines = (n) => (n === 1 ? "1 line needs" : `${n} lines need`)
    const parts = []
    if (issues.needAccount > 0) parts.push(`${lines(issues.needAccount)} an account`)
    if (issues.needAnalytic > 0) parts.push(`${lines(issues.needAnalytic)} a required analytic account`)
    return parts.join(" and ")
  }

  updateBalanceIndicator(balanced, hasValues, debit, credit, issues) {
    const pill = (classes, text) => `<span class="${classes} text-xs font-medium px-2 py-1 rounded-full">${text}</span>`
    const sentence = this.issueSentence(issues)
    let kind, html
    if (!hasValues) {
      kind = "pending"
      html = pill("bg-gray-100 text-gray-600", "Pending") + "<span>Enter debit and credit amounts.</span>"
    } else if (balanced) {
      kind = sentence ? "blocked" : "balanced"
      html = pill("bg-emerald-100 text-emerald-700", "Balanced") +
        (sentence ? `<span>Debit equals credit, but ${sentence} before you can save.</span>` : "<span>Debit equals credit. You can save.</span>")
    } else {
      kind = "unbalanced"
      const diff = this.formatCents(Math.abs(debit - credit))
      const reason = debit > credit ? `Debit exceeds credit by ${diff}` : `Credit exceeds debit by ${diff}`
      // Amber, not red: the entry is simply not finished yet, and the person has done nothing wrong.
      html = pill("bg-amber-100 text-amber-700", `Unbalanced (${diff})`) +
        `<span>${reason}.${sentence ? ` Also, ${sentence}.` : ""}</span>`
    }
    this.balanceIndicatorTarget.innerHTML = html
    this.announce(kind, sentence)
  }

  // Screen readers hear a change of state, not every digit typed.
  announce(kind, sentence) {
    const key = `${kind}|${sentence}`
    if (key === this.lastAnnouncement) return
    this.lastAnnouncement = key
    const text = {
      pending: "",
      balanced: "Balanced. You can save.",
      blocked: `Balanced, but ${sentence} before you can save.`,
      unbalanced: "Unbalanced."
    }[kind]
    this.balanceAnnouncerTarget.textContent = text
  }

  updateSubmitButton(canSave) {
    this.submitButtonTargets.forEach(btn => {
      btn.disabled = !canSave
    })
  }
}

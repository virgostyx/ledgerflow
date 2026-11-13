import { Controller } from "@hotwired/stimulus"

// Account picker: a text field with a list of matching accounts. Works with the mouse and the keyboard
// (ArrowUp/ArrowDown, Enter, Escape, Tab on an exact code) and is announced as a combobox.
let uid = 0
const sources = new WeakMap()

// The chart of accounts is long: a form sends it once, in a JSON script (source-id), and every line reads that one copy.
// A form that still carries it in the accounts value (the invoice form) keeps working.

export default class extends Controller {
  static targets = ["input", "suggestions", "accountId", "suggestion", "error"]
  static values  = { accounts: Array, sourceId: String }

  get accounts() {
    if (!this.hasSourceIdValue) return this.accountsValue
    const script = document.getElementById(this.sourceIdValue)
    if (!script) return []
    if (!sources.has(script)) sources.set(script, JSON.parse(script.textContent || "[]"))
    return sources.get(script)
  }

  connect() {
    this.uid = ++uid
    this.activeIndex = -1
    this.suggestionsTarget.id ||= `account-suggestions-${this.uid}`
    this.suggestionsTarget.setAttribute("role", "listbox")
    this.inputTarget.setAttribute("role", "combobox")
    this.inputTarget.setAttribute("aria-autocomplete", "list")
    this.inputTarget.setAttribute("aria-controls", this.suggestionsTarget.id)
    this.inputTarget.setAttribute("aria-expanded", "false")
  }

  filter(event) {
    if (event?.type === "focus" && this.inputTarget.dataset.suppressOpen) {
      delete this.inputTarget.dataset.suppressOpen
      return
    }
    // Typing changes the text: the account chosen earlier no longer matches it, and must not be saved by mistake.
    if (event?.type === "input" && this.accountIdTarget.value) {
      this.accountIdTarget.value = ""
      this.dispatch("cleared")
    }

    const query = this.inputTarget.value.trim().toLowerCase()
    this.suggestionsTarget.innerHTML = ""
    this.activeIndex = -1

    const matches = query.length === 0
      ? this.accounts.slice(0, 10)
      : this.accounts.filter(a =>
          a.code.toLowerCase().startsWith(query) ||
          (!/^\d/.test(query) && a.label.toLowerCase().includes(query))
        ).slice(0, 10)

    if (event?.type === "input") this.clearError()

    if (matches.length === 0) {
      this.showNoMatch(query)
      return
    }

    matches.forEach((account, index) => {
      const div = document.createElement("div")
      div.textContent = `${account.code} — ${account.label}`
      div.id = `${this.suggestionsTarget.id}-${index}`
      div.setAttribute("role", "option")
      div.setAttribute("aria-selected", "false")
      div.dataset.accountSearchTarget = "suggestion"
      div.dataset.accountId  = account.id
      div.dataset.accountCode = account.code
      div.classList.add("px-3", "py-2", "cursor-pointer", "hover:bg-primary-50", "text-sm")
      div.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this.select(account)
      })
      this.suggestionsTarget.appendChild(div)
    })

    this.matches = matches
    this.suggestionsTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  // Nothing matches: say so, instead of closing the list as if the field were fine.
  showNoMatch(query) {
    const row = document.createElement("div")
    row.id = `${this.suggestionsTarget.id}-none`
    row.setAttribute("role", "option")
    row.setAttribute("aria-disabled", "true")
    row.setAttribute("aria-selected", "false")
    row.classList.add("px-3", "py-2", "text-sm", "text-gray-600")
    row.textContent = `No account matches “${query}”`
    this.suggestionsTarget.appendChild(row)
    this.matches = []
    this.suggestionsTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  keydown(event) {
    const open = !this.suggestionsTarget.classList.contains("hidden")
    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp":
        event.preventDefault()
        if (!open) this.filter()
        this.move(event.key === "ArrowDown" ? 1 : -1)
        break
      case "Enter":
        // Enter picks the highlighted account; it must not submit the entry while the list is open.
        if (open && this.activeIndex >= 0) {
          event.preventDefault()
          this.select(this.matches[this.activeIndex])
        } else if (open) {
          event.preventDefault()
        }
        break
      case "Escape":
        if (open) { event.stopPropagation(); this.close() }
        break
    }
  }

  move(step) {
    const options = this.suggestionTargets
    if (options.length === 0) return
    this.activeIndex = (this.activeIndex + step + options.length) % options.length
    options.forEach((option, index) => {
      const active = index === this.activeIndex
      option.setAttribute("aria-selected", String(active))
      option.classList.toggle("bg-primary-100", active)
    })
    this.inputTarget.setAttribute("aria-activedescendant", options[this.activeIndex].id)
    options[this.activeIndex].scrollIntoView({ block: "nearest" })
  }

  select(account) {
    this.inputTarget.value    = `${account.code} — ${account.label}`
    this.accountIdTarget.value = account.id
    this.clearError()
    this.close()
    // "account-search:selected" is the event the forms listen for (journal-entry-form, invoice-form), with the chosen account in detail.
    this.dispatch("selected", { detail: { accountId: account.id } })
  }

  close() {
    this.suggestionsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  // Leaving the field: a code typed in full is taken as the choice, so Tab after "604000" does not leave the line without an account.
  hideDelayed() {
    this.takeExactCode()
    this.flagUnchosen()
    setTimeout(() => this.close(), 150)
  }

  // Text typed in the field but no account chosen from the list: flag it now, not after a round-trip to the server.
  flagUnchosen() {
    if (!this.inputTarget.value.trim() || this.accountIdTarget.value) return
    this.inputTarget.setAttribute("aria-invalid", "true")
    if (this.hasErrorTarget) {
      this.errorTarget.classList.remove("hidden")
      this.inputTarget.setAttribute("aria-describedby", this.errorTarget.id)
    }
  }

  clearError() {
    this.inputTarget.removeAttribute("aria-invalid")
    this.inputTarget.removeAttribute("aria-describedby")
    if (this.hasErrorTarget) this.errorTarget.classList.add("hidden")
  }

  takeExactCode() {
    if (this.accountIdTarget.value) return
    const typed = this.inputTarget.value.trim().toLowerCase()
    const exact = typed && this.accounts.find(a => a.code.toLowerCase() === typed)
    if (exact) this.select(exact)
  }
}

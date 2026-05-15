import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "suggestions", "accountId", "suggestion"]
  static values  = { accounts: Array }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    this.suggestionsTarget.innerHTML = ""

    if (query.length < 2) {
      this.suggestionsTarget.classList.add("hidden")
      return
    }

    const matches = this.accountsValue.filter(a =>
      a.code.toLowerCase().includes(query) ||
      a.label.toLowerCase().includes(query)
    ).slice(0, 8)

    if (matches.length === 0) {
      this.suggestionsTarget.classList.add("hidden")
      return
    }

    matches.forEach(account => {
      const div = document.createElement("div")
      div.textContent = `${account.code} — ${account.label}`
      div.dataset.accountSearchTarget = "suggestion"
      div.dataset.accountId  = account.id
      div.dataset.accountCode = account.code
      div.classList.add("px-3", "py-2", "cursor-pointer", "hover:bg-indigo-50", "text-sm")
      div.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this.select(account)
      })
      this.suggestionsTarget.appendChild(div)
    })

    this.suggestionsTarget.classList.remove("hidden")
  }

  select(account) {
    this.inputTarget.value    = account.code
    this.accountIdTarget.value = account.id
    this.suggestionsTarget.classList.add("hidden")
    this.inputTarget.dispatchEvent(new Event("account-selected", { bubbles: true }))
  }

  hideDelayed() {
    setTimeout(() => {
      this.suggestionsTarget.classList.add("hidden")
    }, 150)
  }
}

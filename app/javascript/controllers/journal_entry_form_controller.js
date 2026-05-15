import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["linesContainer", "lineTemplate", "debitInput", "creditInput",
                    "balanceIndicator", "submitButton", "line"]

  connect() {
    this.computeBalance()
  }

  addLine() {
    const template = this.lineTemplateTarget.content.cloneNode(true)
    const newIndex = this.linesContainerTarget.querySelectorAll(".entry-lines").length

    template.querySelectorAll("[name]").forEach(el => {
      el.name = el.name.replace("NEW_INDEX", newIndex)
    })
    template.querySelectorAll("[id]").forEach(el => {
      el.id = el.id.replace("NEW_INDEX", newIndex)
    })
    template.querySelectorAll("[for]").forEach(el => {
      el.htmlFor = el.htmlFor.replace("NEW_INDEX", newIndex)
    })

    this.linesContainerTarget.appendChild(template)
    this.computeBalance()
  }

  removeLine(event) {
    const line = event.target.closest(".entry-lines")
    if (line) {
      const destroyInput = line.querySelector("[name$='[_destroy]']")
      if (destroyInput) {
        destroyInput.value = "1"
        line.style.display = "none"
      } else {
        line.remove()
      }
      this.computeBalance()
    }
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
      indicator.innerHTML = '<span class="bg-gray-100 text-gray-600 text-xs font-medium px-2 py-1 rounded-full">En attente</span>'
      return
    }

    if (balanced) {
      indicator.innerHTML = '<span class="bg-emerald-100 text-emerald-700 text-xs font-medium px-2 py-1 rounded-full">Équilibré</span>'
    } else {
      const formatted = diff.toLocaleString("fr-BE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
      indicator.innerHTML = `<span class="bg-red-100 text-red-700 text-xs font-medium px-2 py-1 rounded-full">Déséquilibré (${formatted})</span>`
    }
  }

  updateSubmitButton(balanced) {
    this.submitButtonTargets.forEach(btn => {
      btn.disabled = !balanced
    })
  }
}

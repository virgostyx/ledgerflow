import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "display", "expression", "copyText", "memoryIndicator"]

  connect() {
    this.memory = null
    this.reset()
    this.keydownHandler = this.handleKeydown.bind(this)
    this.outsideClickHandler = this.handleOutsideClick.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keydownHandler)
    document.removeEventListener("click", this.outsideClickHandler)
  }

  handleKeydown(event) {
    const tag = document.activeElement?.tagName
    if (["INPUT", "TEXTAREA", "SELECT"].includes(tag)) return

    switch (event.key) {
      case "0": case "1": case "2": case "3": case "4":
      case "5": case "6": case "7": case "8": case "9":
        event.preventDefault(); this.inputValue(event.key); break
      case ".": case ",":
        event.preventDefault(); this.inputValue("."); break
      case "+":
        event.preventDefault(); this.operationByOp("+"); break
      case "-":
        event.preventDefault(); this.operationByOp("-"); break
      case "*":
        event.preventDefault(); this.operationByOp("*"); break
      case "/":
        event.preventDefault(); this.operationByOp("/"); break
      case "Enter": case "=":
        event.preventDefault(); this.equals(); break
      case "Backspace":
        event.preventDefault(); this.backspace(); break
      case "Delete":
        event.preventDefault(); this.clearEntry(); break
      case "Escape":
        event.preventDefault(); this.close(); break
      case "c": case "C":
        if (!event.ctrlKey && !event.metaKey) { event.preventDefault(); this.reset() }
        break
    }
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
  }

  close() {
    this.panelTarget.classList.add("hidden")
    document.removeEventListener("keydown", this.keydownHandler)
    document.removeEventListener("click", this.outsideClickHandler)
  }

  // ── State ──────────────────────────────────────────────────────────────────

  reset() {
    this.display = "0"
    this.previousValue = null
    this.operator = null
    this.waitingForOperand = false
    this.expressionText = ""
    this.updateUI()
  }

  // ── Input ──────────────────────────────────────────────────────────────────

  input(event) {
    this.inputValue(event.currentTarget.dataset.calcValue)
  }

  inputValue(value) {
    if (value === ".") {
      if (this.waitingForOperand) {
        this.display = "0."
        this.waitingForOperand = false
      } else if (!this.display.includes(".")) {
        this.display += "."
      }
    } else {
      if (this.waitingForOperand || this.display === "0") {
        this.display = value
        this.waitingForOperand = false
      } else {
        if (this.display.replace("-", "").replace(".", "").length < 12) {
          this.display += value
        }
      }
    }
    this.updateUI()
  }

  // ── Operations ─────────────────────────────────────────────────────────────

  operation(event) {
    this.operationByOp(event.currentTarget.dataset.calcOp)
  }

  operationByOp(op) {
    const currentVal = parseFloat(this.display)

    if (this.previousValue !== null && !this.waitingForOperand) {
      const result = this.compute(this.previousValue, currentVal, this.operator)
      if (result === null) return
      this.display = this.formatNumber(result)
      this.previousValue = result
    } else {
      this.previousValue = currentVal
    }

    this.operator = op
    this.waitingForOperand = true
    this.expressionText = `${this.formatNumber(this.previousValue)} ${this.opSymbol(op)}`
    this.updateUI()
  }

  equals() {
    if (this.previousValue === null || this.waitingForOperand) return

    const currentVal = parseFloat(this.display)
    const result = this.compute(this.previousValue, currentVal, this.operator)
    if (result === null) return

    this.expressionText = `${this.formatNumber(this.previousValue)} ${this.opSymbol(this.operator)} ${this.formatNumber(currentVal)} =`
    this.display = this.formatNumber(result)
    this.previousValue = null
    this.operator = null
    this.waitingForOperand = true
    this.updateUI()
  }

  compute(a, b, op) {
    switch (op) {
      case "+": return a + b
      case "-": return a - b
      case "*": return a * b
      case "/":
        if (b === 0) {
          this.display = "Error"
          this.previousValue = null
          this.operator = null
          this.waitingForOperand = true
          this.expressionText = ""
          this.updateUI()
          return null
        }
        return a / b
      default: return b
    }
  }

  opSymbol(op) {
    return { "+": "+", "-": "−", "*": "×", "/": "÷" }[op] || op
  }

  // ── Editing ────────────────────────────────────────────────────────────────

  clearEntry() {
    this.display = "0"
    this.updateUI()
  }

  backspace() {
    if (this.waitingForOperand) return
    this.display = this.display.length > 1 ? this.display.slice(0, -1) : "0"
    this.updateUI()
  }

  // ── Memory ─────────────────────────────────────────────────────────────────

  memoryClear() {
    this.memory = null
    this.updateMemoryIndicator()
  }

  memoryRecall() {
    if (this.memory === null) return
    this.display = this.formatNumber(this.memory)
    this.waitingForOperand = false
    this.updateUI()
  }

  memoryAdd() {
    if (this.display === "Error") return
    this.memory = (this.memory ?? 0) + parseFloat(this.display)
    this.waitingForOperand = true
    this.updateMemoryIndicator()
  }

  memorySubtract() {
    if (this.display === "Error") return
    this.memory = (this.memory ?? 0) - parseFloat(this.display)
    this.waitingForOperand = true
    this.updateMemoryIndicator()
  }

  // ── Clipboard ──────────────────────────────────────────────────────────────

  async copy() {
    if (this.display === "Error" || this.display === "0") return

    const setText = (t) => { if (this.hasCopyTextTarget) this.copyTextTarget.textContent = t }

    try {
      await navigator.clipboard.writeText(this.display)
    } catch {
      const input = document.createElement("input")
      input.value = this.display
      document.body.appendChild(input)
      input.select()
      document.execCommand("copy")
      document.body.removeChild(input)
    }

    setText("✓ Copied!")
    setTimeout(() => setText("Copy result"), 2000)
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  formatNumber(num) {
    if (!isFinite(num)) return "Error"
    const rounded = Math.round(num * 1e10) / 1e10
    const str = rounded.toString()
    return str.length > 14 ? parseFloat(rounded.toPrecision(8)).toString() : str
  }

  updateUI() {
    if (this.hasDisplayTarget) this.displayTarget.textContent = this.display
    if (this.hasExpressionTarget) this.expressionTarget.textContent = this.expressionText
  }

  updateMemoryIndicator() {
    if (this.hasMemoryIndicatorTarget) {
      this.memoryIndicatorTarget.classList.toggle("hidden", this.memory === null)
    }
  }
}

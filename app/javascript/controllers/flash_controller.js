import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    duration:    { type: Number, default: 5000 },
    removeDelay: { type: Number, default: 500 }
  }
  static targets = ["progressBar"]

  connect() {
    this.element.classList.remove("opacity-0", "translate-y-[-1rem]")
    this.element.classList.add("opacity-100", "translate-y-0")

    this.remaining = this.durationValue
    this.startCountdown()
  }

  disconnect() {
    if (this.timeoutId) clearTimeout(this.timeoutId)
  }

  close() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
      this.timeoutId = null
    }

    this.element.classList.remove("opacity-100", "translate-y-0")
    this.element.classList.add("opacity-0", "translate-y-[-1rem]")

    setTimeout(() => this.element.remove(), this.removeDelayValue)
  }

  pause() {
    if (!this.timeoutId) return

    clearTimeout(this.timeoutId)
    this.timeoutId = null
    this.remaining -= Date.now() - this.startedAt

    if (this.hasProgressBarTarget) {
      const frozenWidth = (this.remaining / this.durationValue) * 100
      this.progressBarTarget.style.transition = "none"
      this.progressBarTarget.style.width = `${frozenWidth}%`
    }
  }

  resume() {
    if (this.timeoutId) return
    this.startCountdown()
  }

  startCountdown() {
    this.startedAt = Date.now()

    if (this.hasProgressBarTarget) {
      const bar = this.progressBarTarget
      bar.style.transition = "none"
      bar.getBoundingClientRect()
      bar.style.transition = `width ${this.remaining}ms linear`
      bar.style.width = "0%"
    }

    this.timeoutId = setTimeout(() => this.close(), this.remaining)
  }
}

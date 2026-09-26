import { Controller } from "@hotwired/stimulus"
import { get } from "@github/webauthn-json"

export default class extends Controller {
  static targets = ["email", "status", "button"]
  static values = { optionsUrl: String, verifyUrl: String }

  async connect() {
    this.abortController = new AbortController()

    if (await this.conditionalUiAvailable()) {
      this.authenticate("conditional")
    } else if (this.webauthnAvailable()) {
      this.showButton()
    }
  }

  disconnect() {
    this.abortController.abort()
  }

  async conditionalUiAvailable() {
    return !!(
      window.PublicKeyCredential &&
      window.PublicKeyCredential.isConditionalMediationAvailable &&
      (await PublicKeyCredential.isConditionalMediationAvailable())
    )
  }

  webauthnAvailable() {
    return !!window.PublicKeyCredential
  }

  showButton() {
    if (this.hasButtonTarget) this.buttonTarget.classList.remove("hidden")
  }

  async authenticate(mediation = "optional") {
    this.hideStatus()

    const options = await (await fetch(this.optionsUrlValue, { headers: { Accept: "application/json" } })).json()

    let credential
    try {
      credential = await get({ mediation, publicKey: options, signal: this.abortController.signal })
    } catch (error) {
      if (error.name !== "AbortError" && mediation !== "conditional") {
        this.showStatus("Passkey sign-in was cancelled or failed.")
      }
      return
    }

    const response = await fetch(this.verifyUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ credential })
    })
    const result = await response.json()

    if (response.ok) {
      window.location.href = result.redirect_to
    } else {
      this.showStatus(result.error)
    }
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.remove("hidden")
  }

  hideStatus() {
    if (!this.hasStatusTarget) return
    this.statusTarget.classList.add("hidden")
  }
}

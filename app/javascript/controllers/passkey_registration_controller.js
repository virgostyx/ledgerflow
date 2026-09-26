import { Controller } from "@hotwired/stimulus"
import { create } from "@github/webauthn-json"

export default class extends Controller {
  static targets = ["form", "nickname", "error", "backupCodes", "backupCodesList", "downloadLink"]
  static values = { optionsUrl: String, createUrl: String }

  async register() {
    this.hideError()
    const nickname = this.nicknameTarget.value.trim()

    if (!nickname) {
      this.showError("Please enter a name for this passkey.")
      return
    }

    const options = await (await fetch(this.optionsUrlValue, { headers: { Accept: "application/json" } })).json()

    let credential
    try {
      credential = await create({ publicKey: options })
    } catch (error) {
      console.error("Passkey registration failed:", error.name, error.message)
      this.showError(this.errorMessageFor(error))
      return
    }

    const response = await fetch(this.createUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ credential, nickname })
    })
    const result = await response.json()

    if (!response.ok) {
      this.showError(result.error)
      return
    }

    if (result.backup_codes) {
      this.showBackupCodes(result.backup_codes)
    } else {
      window.Turbo.visit(window.location.pathname)
    }
  }

  errorMessageFor(error) {
    switch (error.name) {
      case "NotAllowedError":
        return "Passkey registration was cancelled, timed out, or no authenticator responded."
      case "NotSupportedError":
        return "No authenticator on this device supports the required security options (biometric/PIN or a FIDO2 security key)."
      case "SecurityError":
        return "This page's address doesn't match the one passkeys are registered for."
      case "InvalidStateError":
        return "A passkey for this account is already registered on this authenticator."
      default:
        return "Passkey registration was cancelled or failed."
    }
  }

  showBackupCodes(codes) {
    this.formTarget.classList.add("hidden")
    this.backupCodesListTarget.replaceChildren(
      ...codes.map((code) => {
        const li = document.createElement("li")
        li.className = "font-mono text-sm text-center p-2 bg-gray-50 border border-gray-200 rounded"
        li.textContent = code
        return li
      })
    )

    const today = new Date().toISOString().slice(0, 10)
    const fileBody = [
      "LedgerFlow account recovery codes",
      `Generated: ${today}`,
      "Each code can be used once to sign in if you lose access to your passkey.",
      "", ...codes
    ].join("\n")
    this.downloadLinkTarget.href = `data:text/plain;charset=utf-8,${encodeURIComponent(fileBody)}`
    this.downloadLinkTarget.download = `ledgerflow-recovery-codes-${today}.txt`

    this.backupCodesTarget.classList.remove("hidden")
  }

  done() {
    window.Turbo.visit(window.location.pathname)
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  hideError() {
    this.errorTarget.classList.add("hidden")
  }
}

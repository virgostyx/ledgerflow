import { Turbo } from "@hotwired/turbo-rails"

// Replace the native browser confirm() with the custom #confirm-modal.
// confirm_controller.js resolves window.confirmResolver on Confirm/Cancel.
Turbo.setConfirmMethod((message) => new Promise((resolve) => {
  const modal = document.getElementById("confirm-modal")
  if (!modal) return resolve(window.confirm(message))

  window.confirmResolver = resolve
  modal.querySelector('[data-confirm-target="message"]').textContent = message
  modal.classList.remove("hidden")
  document.body.style.overflow = "hidden"
  setTimeout(() => modal.querySelector('[data-confirm-target="confirmButton"]')?.focus(), 100)
}))

import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Drop files on the upload form; they are sent in one request with a progress bar, then the list is shown (F03).
export default class extends Controller {
  static targets = ["status", "bar", "label"]

  over(event) { event.preventDefault(); this.element.classList.add("bg-primary-50") }
  leave() { this.element.classList.remove("bg-primary-50") }

  drop(event) {
    event.preventDefault()
    this.leave()
    if (event.dataTransfer.files.length === 0) return
    this.element.querySelector("input[type=file]").files = event.dataTransfer.files
    this.element.requestSubmit()
  }

  submit(event) {
    event.preventDefault()
    const xhr = new XMLHttpRequest()
    xhr.open("POST", this.element.action)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.setRequestHeader("X-CSRF-Token", document.querySelector("meta[name=csrf-token]")?.content || "")
    xhr.upload.onprogress = (e) => { if (e.lengthComputable) this.show(Math.round(100 * e.loaded / e.total)) }
    xhr.onload = () => xhr.status === 200 ? Turbo.visit(window.location.href, { action: "replace" }) : this.fail()
    xhr.onerror = () => this.fail()
    this.show(0)
    xhr.send(new FormData(this.element))
  }

  show(percent) {
    this.statusTarget.hidden = false
    this.barTarget.style.width = `${percent}%`
    this.labelTarget.textContent = percent < 100 ? `Uploading… ${percent}%` : "Reading the files…"
  }

  fail() { this.labelTarget.textContent = "The upload failed. Try again." }
}

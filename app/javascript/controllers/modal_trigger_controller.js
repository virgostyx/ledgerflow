import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static outlets = ["modal"]

  open(event) {
    if (event) event.preventDefault()

    if (this.hasModalOutlet) {
      this.modalOutlets.forEach(outlet => outlet.open())
    }
  }
}

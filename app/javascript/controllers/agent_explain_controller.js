import { Controller } from "@hotwired/stimulus"

// The "Explain" button of a figure: the panel opens (it listens for this event) while the conversation about the figure loads into it.
export default class extends Controller {
  open() { window.dispatchEvent(new CustomEvent("agent:open")) }
}

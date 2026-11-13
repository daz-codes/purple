import { Controller } from "@hotwired/stimulus"

// A toast fades away on its own after a few seconds, or when dismissed.
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => this.dismiss(), 8000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.remove()
  }
}

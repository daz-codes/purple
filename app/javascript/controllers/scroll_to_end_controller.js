import { Controller } from "@hotwired/stimulus"

// A conversation opens at its newest message, as a phone's does.
export default class extends Controller {
  connect() {
    this.element.scrollTop = this.element.scrollHeight
  }
}

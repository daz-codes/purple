import { Controller } from "@hotwired/stimulus"

// The in-game browser window. Opens as a modal; Escape closes the tab through the server like the
// "Close tab" button, so closing is always a recorded move.
export default class extends Controller {
  static targets = [ "close" ]

  connect() {
    if (!this.element.open) this.element.showModal()
  }

  cancel(event) {
    event.preventDefault()
    if (this.hasCloseTarget) this.closeTarget.click()
  }
}

import { Controller } from "@hotwired/stimulus"

// The in-game browser window. Opens as a modal; Escape closes the tab through the server like the
// "Close tab" button, so closing is always a recorded move.
//
// Chrome won't let a page cancel a second Escape without a click in between, so the dialog can close
// on its own. When that happens the close is still sent to the server; if the server refuses, the
// next response re-renders the tab.
export default class extends Controller {
  static targets = [ "close" ]

  connect() {
    this.closing = false
    if (!this.element.open) this.element.showModal()
  }

  cancel(event) {
    event.preventDefault()
    this.requestClose()
  }

  closed() {
    this.requestClose()
  }

  requestClose() {
    if (this.closing || !this.hasCloseTarget) return

    this.closing = true
    this.closeTarget.click()
  }
}

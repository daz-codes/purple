import { Controller } from "@hotwired/stimulus"

// Shows where a link in a message really goes while it's hovered or focused, like a mail
// client's status bar. Hovering is free in the game, as it is in real life.
export default class extends Controller {
  static targets = [ "bar" ]

  show(event) {
    const link = event.target.closest("[data-actual-url]")
    if (!link || !this.hasBarTarget) return

    this.barTarget.textContent = link.dataset.actualUrl
    this.barTarget.hidden = false
  }

  hide(event) {
    if (!event.target.closest("[data-actual-url]") || !this.hasBarTarget) return

    this.barTarget.hidden = true
  }
}

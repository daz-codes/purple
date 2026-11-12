import { Controller } from "@hotwired/stimulus"

// Flag mode in the reading pane. While it's on, clicking (or pressing Enter or Space on) any part of
// the message with a data-anchor flags it instead of doing what it normally does: a link isn't
// visited and an attachment isn't opened. Only the neutral anchor is posted; the server records the
// flag and sends the reader back, still in flag mode. Every part is flaggable, so flagging gives
// nothing away.
export default class extends Controller {
  static targets = [ "toggle", "banner", "form", "anchor" ]
  static values = { active: Boolean, flagged: Array }

  connect() {
    this.render()
  }

  toggle() {
    this.activeValue = !this.activeValue
  }

  activeValueChanged() {
    this.render()
  }

  pick(event) {
    const part = this.partFor(event)
    if (!part) return

    event.preventDefault()
    event.stopImmediatePropagation()
    if (this.submitting) return
    this.submitting = true

    this.anchorTarget.value = part.dataset.anchor
    this.formTarget.requestSubmit()
  }

  keydown(event) {
    if (event.key === "Enter" || event.key === " ") this.pick(event)
  }

  // The flaggable part an event landed on, if flag mode is on.
  partFor(event) {
    if (!this.activeValue || !this.hasFormTarget) return null

    const part = event.target.closest("[data-anchor]")
    return part && this.element.contains(part) ? part : null
  }

  render() {
    this.element.classList.toggle("flag-mode", this.activeValue)
    this.toggleTargets.forEach((button) => button.setAttribute("aria-pressed", this.activeValue))
    this.bannerTargets.forEach((banner) => banner.hidden = !this.activeValue)

    this.element.querySelectorAll("[data-anchor]").forEach((part) => {
      part.classList.toggle("flagged", this.flaggedValue.includes(part.dataset.anchor))
      // Paragraphs and headers can be reached by keyboard while flagging. Links already can.
      if (this.activeValue && !part.hasAttribute("tabindex")) {
        part.setAttribute("tabindex", "0")
        part.dataset.flagModeFocusable = ""
      } else if (!this.activeValue && "flagModeFocusable" in part.dataset) {
        part.removeAttribute("tabindex")
        delete part.dataset.flagModeFocusable
      }
    })
  }
}

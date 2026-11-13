import { Controller } from "@hotwired/stimulus"

const BLOCK = /^p\d+$/

// Flag mode in the reading pane. While it's on:
// - dragging across words in a paragraph flags just those words (posted as the paragraph's anchor and
//   the character range of the selection in its text);
// - clicking a sentence, a header, a link or an attachment flags that whole part (posted as its
//   neutral anchor), instead of doing what it normally does: a link isn't visited;
// - clicking words that are already highlighted takes that highlight off.
// Only anchors and ranges are posted. The server records the flag and sends the reader back, still in
// flag mode. Every part and every word is flaggable, so flagging gives nothing away.
//
// Highlights are drawn with the CSS Custom Highlight API, so the message's markup is never changed and
// the text offsets stay the same as the server's.
export default class extends Controller {
  static targets = [ "toggle", "banner", "form", "anchor", "from", "to" ]
  static values = { active: Boolean, flags: Array }

  connect() {
    this.render()
  }

  disconnect() {
    CSS.highlights?.delete("flagged")
  }

  toggle() {
    this.activeValue = !this.activeValue
  }

  activeValueChanged() {
    this.render()
  }

  pick(event) {
    if (!this.activeValue || !this.hasFormTarget) return

    const flag = this.selectedWords() || this.clickedPart(event)
    if (!flag) return

    event.preventDefault()
    event.stopImmediatePropagation()
    window.getSelection()?.removeAllRanges()
    this.submit(flag)
  }

  keydown(event) {
    if (event.key === "Enter" || event.key === " ") this.pick(event)
  }

  // A refused flag doesn't replace the reader (and with it this controller), so the guard must be
  // reset whenever a submission finishes, however it went.
  submitted() {
    this.submitting = false
  }

  submit({ anchor, from = "", to = "" }) {
    if (this.submitting) return
    this.submitting = true

    this.anchorTarget.value = anchor
    this.fromTarget.value = from
    this.toTarget.value = to
    this.formTarget.requestSubmit()
  }

  // Words dragged over within one paragraph, as { anchor, from, to }.
  selectedWords() {
    const selection = window.getSelection()
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null

    const range = selection.getRangeAt(0)
    const block = this.blockOf(range.startContainer)
    if (!block || block !== this.blockOf(range.endContainer)) return null

    const from = this.offsetIn(block, range.startContainer, range.startOffset)
    const to = this.offsetIn(block, range.endContainer, range.endOffset)
    return to > from ? { anchor: block.dataset.anchor, from, to } : null
  }

  // The part a click landed on: a highlight to take off, or a sentence, header, link or attachment.
  clickedPart(event) {
    const part = event.target.closest("[data-anchor]")
    if (!part || !this.element.contains(part)) return null

    const block = this.blockOf(part)
    const offset = block && this.clickOffset(event, block)
    if (offset != null) {
      const highlight = this.flagsValue.find((flag) => flag.anchor === block.dataset.anchor && flag.from <= offset && offset < flag.to)
      if (highlight) return highlight
    }

    return BLOCK.test(part.dataset.anchor) ? null : { anchor: part.dataset.anchor }
  }

  blockOf(node) {
    let element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
    while (element && this.element.contains(element)) {
      if (BLOCK.test(element.dataset.anchor || "")) return element
      element = element.parentElement
    }
    return null
  }

  offsetIn(block, node, offset) {
    const range = document.createRange()
    range.setStart(block, 0)
    range.setEnd(node, offset)
    return range.toString().length
  }

  clickOffset(event, block) {
    if (event.clientX === undefined) return null

    const caret = document.caretPositionFromPoint?.(event.clientX, event.clientY)
    if (caret) return block.contains(caret.offsetNode) ? this.offsetIn(block, caret.offsetNode, caret.offset) : null

    const range = document.caretRangeFromPoint?.(event.clientX, event.clientY)
    return range && block.contains(range.startContainer) ? this.offsetIn(block, range.startContainer, range.startOffset) : null
  }

  // A DOM Range covering characters from...to of a block's text.
  rangeFor(block, from, to) {
    const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT)
    const range = document.createRange()
    let seen = 0
    let started = false
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const length = node.textContent.length
      if (!started && from <= seen + length) {
        range.setStart(node, from - seen)
        started = true
      }
      if (started && to <= seen + length) {
        range.setEnd(node, to - seen)
        return range
      }
      seen += length
    }
    return null
  }

  render() {
    this.element.classList.toggle("flag-mode", this.activeValue)
    this.toggleTargets.forEach((button) => button.setAttribute("aria-pressed", this.activeValue))
    this.bannerTargets.forEach((banner) => banner.hidden = !this.activeValue)

    const whole = this.flagsValue.filter((flag) => flag.from == null).map((flag) => flag.anchor)
    this.element.querySelectorAll("[data-anchor]").forEach((part) => {
      part.classList.toggle("flagged", whole.includes(part.dataset.anchor))
      // Sentences and headers can be reached by keyboard while flagging. Links already can.
      const focusable = this.activeValue && !BLOCK.test(part.dataset.anchor)
      if (focusable && !part.hasAttribute("tabindex")) {
        part.setAttribute("tabindex", "0")
        part.dataset.flagModeFocusable = ""
      } else if (!focusable && "flagModeFocusable" in part.dataset) {
        part.removeAttribute("tabindex")
        delete part.dataset.flagModeFocusable
      }
    })

    this.drawHighlights()
  }

  drawHighlights() {
    if (!window.CSS?.highlights) return

    const ranges = this.flagsValue.filter((flag) => flag.from != null).flatMap((flag) => {
      const block = [ ...this.element.querySelectorAll("[data-anchor]") ].find((node) => node.dataset.anchor === flag.anchor)
      const range = block && this.rangeFor(block, flag.from, flag.to)
      return range ? [ range ] : []
    })
    CSS.highlights.set("flagged", new Highlight(...ranges))
  }
}

import { Controller } from "@hotwired/stimulus"

const BLOCK = /^p\d+$/
const SENTENCE = /^p\d+s\d+$/

// Flag mode in the reading pane. While it's on:
// - dragging across words in a paragraph flags just those words (posted as the paragraph's anchor and
//   the character range of the selection in its text);
// - clicking a sentence, a header, a link or an attachment flags that whole part (posted as its
//   neutral anchor), instead of doing what it normally does: a link isn't visited;
// - clicking words that are already highlighted takes that highlight off.
// Only anchors and ranges are posted. The server records the flag and sends the reader back, still in
// flag mode. Every part and every word is flaggable, so flagging gives nothing away.
//
// The same picking saves notes in "notes" mode (mode value "note"): words or a sentence are posted to
// the notes form instead, and clicking a saved note takes it off. Headers, links and attachments can't
// be saved as notes.
//
// Offsets count characters of the paragraph's normalised text, the same way the server does
// (Message::Paragraph): the text nodes in order, every run of whitespace collapsed to one space, and the
// ends trimmed. Highlights are drawn with the CSS Custom Highlight API, so the message's markup is never
// changed.
export default class extends Controller {
  static targets = [ "toggle", "banner", "form", "anchor", "from", "to", "noteToggle", "noteBanner", "noteForm" ]
  static values = { active: Boolean, mode: { type: String, default: "flag" }, flags: Array, notes: Array }

  connect() {
    this.render()
  }

  disconnect() {
    CSS.highlights?.delete("flagged")
    CSS.highlights?.delete("noted")
  }

  toggle() {
    this.switchTo("flag")
  }

  toggleNotes() {
    this.switchTo("note")
  }

  // Pressing a mode's button turns it on, or off if it's already the one on.
  switchTo(mode) {
    const on = !(this.activeValue && this.modeValue === mode)
    this.modeValue = mode
    this.activeValue = on
  }

  activeValueChanged() {
    this.render()
  }

  modeValueChanged() {
    this.render()
  }

  get noting() {
    return this.activeValue && this.modeValue === "note"
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
    const form = this.noting ? (this.hasNoteFormTarget && this.noteFormTarget) : this.formTarget
    if (this.submitting || !form) return
    this.submitting = true

    form.elements.anchor.value = anchor
    form.elements.from.value = from
    form.elements.to.value = to
    form.requestSubmit()
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
      const marks = this.noting ? this.notesValue : this.flagsValue
      const highlight = marks.find((mark) => mark.anchor === block.dataset.anchor && mark.from <= offset && offset < mark.to)
      if (highlight) return highlight
    }

    if (BLOCK.test(part.dataset.anchor)) return null
    // Notes are words: only a sentence can be saved whole.
    if (this.noting && !SENTENCE.test(part.dataset.anchor)) return null
    return { anchor: part.dataset.anchor }
  }

  blockOf(node) {
    let element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
    while (element && this.element.contains(element)) {
      if (BLOCK.test(element.dataset.anchor || "")) return element
      element = element.parentElement
    }
    return null
  }

  // How many characters of the block's normalised text come before raw position (node, offset).
  offsetIn(block, node, offset) {
    const range = document.createRange()
    range.setStart(block, 0)
    range.setEnd(node, offset)
    const before = range.toString().replace(/\s+/g, " ").replace(/^ /, "").length
    return Math.min(before, block.textContent.replace(/\s+/g, " ").trim().length)
  }

  clickOffset(event, block) {
    if (event.clientX === undefined) return null

    const caret = document.caretPositionFromPoint?.(event.clientX, event.clientY)
    if (caret) return block.contains(caret.offsetNode) ? this.offsetIn(block, caret.offsetNode, caret.offset) : null

    const range = document.caretRangeFromPoint?.(event.clientX, event.clientY)
    return range && block.contains(range.startContainer) ? this.offsetIn(block, range.startContainer, range.startOffset) : null
  }

  // A DOM Range covering characters from...to of a block's normalised text.
  rangeFor(block, from, to) {
    const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT)
    const range = document.createRange()
    let count = 0, started = false, afterSpace = false, start = null, last = null
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.textContent
      for (let i = 0; i < text.length; i++) {
        if (!start && count >= from) start = [ node, i ]
        if (start && count >= to) {
          range.setStart(...start)
          range.setEnd(node, i)
          return range
        }
        if (/\s/.test(text[i])) {
          if (started && !afterSpace) count++
          afterSpace = true
        } else {
          started = true
          afterSpace = false
          count++
        }
      }
      last = node
    }
    if (!start || count < to) return null
    range.setStart(...start)
    range.setEnd(last, last.textContent.length)
    return range
  }

  render() {
    const flagging = this.activeValue && !this.noting
    this.element.classList.toggle("flag-mode", this.activeValue)
    this.toggleTargets.forEach((button) => button.setAttribute("aria-pressed", flagging))
    this.bannerTargets.forEach((banner) => banner.hidden = !flagging)
    this.noteToggleTargets.forEach((button) => button.setAttribute("aria-pressed", this.noting))
    this.noteBannerTargets.forEach((banner) => banner.hidden = !this.noting)

    const whole = this.flagsValue.filter((flag) => flag.from == null).map((flag) => flag.anchor)
    this.element.querySelectorAll("[data-anchor]").forEach((part) => {
      part.classList.toggle("flagged", whole.includes(part.dataset.anchor))
      // Sentences and headers can be reached by keyboard while flagging (only sentences while saving
      // notes). Links already can.
      const focusable = this.activeValue && !BLOCK.test(part.dataset.anchor) && (!this.noting || SENTENCE.test(part.dataset.anchor))
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

    CSS.highlights.set("flagged", new Highlight(...this.rangesFor(this.flagsValue)))
    CSS.highlights.set("noted", new Highlight(...this.rangesFor(this.notesValue)))
  }

  rangesFor(marks) {
    return marks.filter((mark) => mark.from != null).flatMap((mark) => {
      const block = [ ...this.element.querySelectorAll("[data-anchor]") ].find((node) => node.dataset.anchor === mark.anchor)
      const range = block && this.rangeFor(block, mark.from, mark.to)
      return range ? [ range ] : []
    })
  }
}

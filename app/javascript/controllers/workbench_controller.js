import { Controller } from "@hotwired/stimulus"
import { OPERATIONS, bytesFromText, textFromBytes, hexFromBytes } from "workbench/operations"

// The Workbench: a chain of operations over what the player has loaded. It runs entirely in the
// browser and never knows a flag: answers are only ever checked when submitted.
//
// The Workbench section is data-turbo-permanent, so it survives switching intercepts while this
// controller (on a wrapper that isn't) comes and goes. So every bit of state lives in the DOM: the
// input's text (or, for a file, its bytes on the textarea element), and each step as an <li> holding
// its operation and argument. Each run reads it all afresh.
export default class extends Controller {
  static targets = ["input", "source", "operation", "steps", "stepTemplate", "output", "view"]

  connect() {
    this.run()
  }

  loadText({ params: { text, name } }) {
    this.inputTarget.workbenchBytes = null
    this.inputTarget.readOnly = false
    this.inputTarget.value = text
    this.sourceTarget.textContent = `Loaded: ${name}`
    this.run()
  }

  async loadFile({ params: { url, name } }) {
    this.sourceTarget.textContent = `Loading ${name}…`
    try {
      const response = await fetch(url, { credentials: "same-origin" })
      if (!response.ok) throw new Error(response.statusText)

      const bytes = new Uint8Array(await response.arrayBuffer())
      this.inputTarget.workbenchBytes = bytes
      this.inputTarget.readOnly = true
      this.inputTarget.value = `${name}: ${bytes.length.toLocaleString()} bytes of file. Load a text intercept to type here again.`
      this.sourceTarget.textContent = `Loaded: ${name}`
    } catch {
      this.sourceTarget.textContent = `Couldn't load ${name}. Try again.`
    }
    this.run()
  }

  typed() {
    this.inputTarget.workbenchBytes = null
    this.run()
  }

  add() {
    const option = this.operationTarget.selectedOptions[0]
    const step = this.stepTemplateTarget.content.firstElementChild.cloneNode(true)
    step.dataset.operation = option.value
    step.querySelector("[data-role=label]").textContent = option.textContent

    const argument = option.dataset.argument
    if (argument) {
      const field = step.querySelector("[data-role=argument]")
      const input = step.querySelector("[data-role=argument-input]")
      field.hidden = false
      step.querySelector("[data-role=argument-label]").textContent = ARGUMENT_LABELS[argument]
      input.setAttribute("aria-label", `${ARGUMENT_LABELS[argument]} for ${option.textContent}`)
      if (argument === "shift") {
        input.type = "number"
        input.min = "1"
        input.max = "25"
        input.value = "13"
      }
    }

    this.stepsTarget.append(step)
    step.querySelector(argument ? "[data-role=argument-input]" : "[data-action~='workbench#remove']").focus()
    this.run()
  }

  remove(event) {
    event.target.closest("li").remove()
    this.run()
  }

  // Runs every step in turn. A step that fails says why, and the steps after it wait. Runs can overlap
  // (loading an image is asynchronous), so only the latest one gets to write its results.
  async run() {
    const run = (this.runCount = (this.runCount || 0) + 1)
    let bytes = this.inputTarget.workbenchBytes || bytesFromText(this.inputTarget.value)
    let failed = false

    for (const step of this.stepsTarget.children) {
      const error = step.querySelector("[data-role=error]")
      const view = step.querySelector("[data-role=view]")
      let message = null
      let shown = null

      if (failed) {
        message = "Waiting for the step above."
      } else {
        try {
          const argument = step.querySelector("[data-role=argument-input]").value
          const outcome = await OPERATIONS[step.dataset.operation](bytes, argument)
          bytes = outcome.bytes
          shown = outcome.view
        } catch (problem) {
          message = problem.message || "That step didn't work."
          failed = true
        }
      }
      if (run !== this.runCount) return

      error.hidden = !message
      error.textContent = message || ""
      view.hidden = !shown
      view.replaceChildren(...(shown ? [this.renderView(shown)] : []))
    }

    const hex = this.viewTargets.find((radio) => radio.checked)?.value === "hex"
    this.outputTarget.textContent = hex ? hexFromBytes(bytes, " ") : textFromBytes(bytes)
  }

  // A letter-frequency chart: a table with a meter per letter (no inline styles, for the CSP).
  renderView({ rows, max }) {
    const table = document.createElement("table")
    table.className = "w-full max-w-md text-xs"
    const caption = table.createCaption()
    caption.className = "text-left text-ink-muted"
    caption.textContent = "Letter frequencies. In English the most common are E, T, A, O, I and N."
    for (const { label, count, total } of rows) {
      const row = table.insertRow()
      row.insertCell().textContent = label
      const meter = document.createElement("meter")
      meter.className = "gauge w-full"
      meter.min = 0
      meter.max = max
      meter.value = count
      meter.setAttribute("aria-label", `${label}: ${count}`)
      row.insertCell().append(meter)
      row.insertCell().textContent = total ? `${count} (${Math.round((count / total) * 100)}%)` : "0"
    }
    return table
  }
}

const ARGUMENT_LABELS = { shift: "Shift", key: "Key", text: "Key", hex: "Hex key", pattern: "Pattern" }

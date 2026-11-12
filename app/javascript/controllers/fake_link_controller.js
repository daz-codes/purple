import { Controller } from "@hotwired/stimulus"

// One visit at a time across every link, so a double-click or held Enter posts once. The server
// also refuses to reopen the page that's already open.
let visiting = false

// A link in a message. It never navigates: clicking (or Enter) posts only the link's neutral key
// to the server, which decides what the in-game browser shows. The URL comes from the message body's
// data-link-visit-url, with __key__ standing for the key.
export default class extends Controller {
  connect() {
    this.element.addEventListener("click", this.visit)
    this.element.addEventListener("keydown", this.keydown)
  }

  disconnect() {
    this.element.removeEventListener("click", this.visit)
    this.element.removeEventListener("keydown", this.keydown)
  }

  keydown = (event) => {
    if (event.key === "Enter" || event.key === " ") this.visit(event)
  }

  visit = (event) => {
    event.preventDefault()
    const template = this.element.closest("[data-link-visit-url]")?.dataset.linkVisitUrl
    if (!template || visiting) return
    visiting = true

    const form = document.createElement("form")
    form.method = "post"
    form.action = template.replace("__key__", encodeURIComponent(this.element.dataset.linkKey))
    form.hidden = true

    const token = document.querySelector("meta[name=csrf-token]")?.content
    if (token) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "authenticity_token"
      input.value = token
      form.append(input)
    }

    form.addEventListener("turbo:submit-end", () => {
      visiting = false
      form.remove()
    })
    document.body.append(form)
    form.requestSubmit()
  }
}

import { Controller } from "@hotwired/stimulus"

// The phone in a message shift shows one screen at a time: the conversation list or one
// conversation. Opening a conversation is a move the server records (like reading an email); going
// back to the list is only a change of view, so it happens here.
export default class extends Controller {
  static targets = [ "list", "thread" ]
  static values = { screen: String }

  screenValueChanged() {
    this.listTarget.hidden = this.screenValue !== "list"
    this.threadTarget.hidden = this.screenValue === "list"
  }

  showList() {
    this.screenValue = "list"
  }

  // A conversation in the list was opened, and the server has sent it back.
  opened(event) {
    if (event.detail.success) this.screenValue = "thread"
  }
}

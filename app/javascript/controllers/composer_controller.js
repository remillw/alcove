import { Controller } from "@hotwired/stimulus"

// Enter sends, Shift+Enter breaks the line. Each submit carries a fresh nonce, so a double click or a retried
// request creates one message (unique index on conversation_id + client_nonce).
export default class extends Controller {
  static targets = ["input", "nonce", "send"]

  connect() {
    this.element.addEventListener("submit", () => {
      this.nonceTarget.value = crypto.randomUUID()
      this.sendTarget.disabled = true
    })
    if (window.matchMedia("(hover: hover)").matches) this.inputTarget.focus()
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
    event.preventDefault()
    if (this.inputTarget.value.trim()) this.element.requestSubmit()
  }

  reset(event) {
    this.sendTarget.disabled = false
    if (event.detail.success) {
      this.inputTarget.value = ""
      this.inputTarget.focus()
    }
  }
}

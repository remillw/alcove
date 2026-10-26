import { Controller } from "@hotwired/stimulus"

// A suggestion is sent as if typed: it fills the box and submits the same form (same nonce, same rules).
export default class extends Controller {
  send(event) {
    const form = document.querySelector("#composer form")
    const input = form?.querySelector("textarea")
    if (!input) return
    input.value = event.currentTarget.textContent.trim()
    form.requestSubmit()
    this.element.replaceChildren()
  }
}

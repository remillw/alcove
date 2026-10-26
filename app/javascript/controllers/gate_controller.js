import { Controller } from "@hotwired/stimulus"

// Age and AI notice, asked once, right before the first conversation (not as a wall on arrival).
export default class extends Controller {
  static targets = ["dialog", "box", "adult"]
  static values = { adult: Number }

  check(event) {
    if (this.adultValue) return
    event.preventDefault()
    this.pending = event.target
    this.dialogTarget.showModal()
  }

  confirm() {
    if (!this.boxTarget.checked) return
    this.adultValue = 1
    this.adultTargets.forEach((input) => (input.value = "1"))
    this.pending?.requestSubmit()
  }

  cancel() { this.dialogTarget.close() }
}

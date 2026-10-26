import { Controller } from "@hotwired/stimulus"

// The character's keepsake: a side panel on large screens, a bottom sheet on phones.
export default class extends Controller {
  static targets = ["panel", "button"]

  toggle() {
    const open = this.panelTarget.classList.toggle("is-open")
    this.buttonTarget.setAttribute("aria-expanded", open)
    if (open) document.getElementById("keepsake_badge")?.replaceWith(Object.assign(document.createElement("span"), { id: "keepsake_badge" }))
  }
}

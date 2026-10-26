import { Controller } from "@hotwired/stimulus"

// The home page shows one character at a time, a short exchange written line by line; then the next one.
export default class extends Controller {
  static targets = ["slide"]

  connect() {
    this.index = 0
    this.reduced = matchMedia("(prefers-reduced-motion: reduce)").matches
    this.play()
    this.element.addEventListener("pointerenter", () => (this.paused = true))
    this.element.addEventListener("pointerleave", () => (this.paused = false))
  }

  disconnect() { clearTimeout(this.timer) }

  play() {
    const slide = this.slideTargets[this.index]
    this.slideTargets.forEach((s) => (s.hidden = s !== slide))
    const lines = [...slide.querySelectorAll(".spotlight__log .msg")]
    if (this.reduced) { lines.forEach((l) => (l.hidden = false)); return }
    lines.forEach((l) => (l.hidden = true))
    let delay = 400
    lines.forEach((line) => {
      this.after(delay, () => (line.hidden = false))
      delay += 900 + line.textContent.length * 18
    })
    this.after(delay + 2600, () => this.next())
  }

  next() {
    if (this.paused) return this.after(1500, () => this.next())
    this.index = (this.index + 1) % this.slideTargets.length
    this.play()
  }

  after(ms, fn) { this.timer = setTimeout(fn, ms) }
}

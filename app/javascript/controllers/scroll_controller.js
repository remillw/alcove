import { Controller } from "@hotwired/stimulus"

// The log scrolls inside the chat: keep the latest message in view while a reply is being written,
// unless the reader scrolled up to read.
export default class extends Controller {
  connect() {
    this.follow = true
    this.onScroll = () => {
      const el = this.element
      this.follow = el.scrollHeight - el.scrollTop - el.clientHeight < 160
    }
    this.element.addEventListener("scroll", this.onScroll, { passive: true })
    this.observer = new MutationObserver(() => { if (this.follow) this.bottom() })
    this.observer.observe(this.element, { childList: true, subtree: true, characterData: true })
    this.bottom()
  }

  bottom() { this.element.scrollTop = this.element.scrollHeight }

  disconnect() {
    this.observer.disconnect()
    this.element.removeEventListener("scroll", this.onScroll)
  }
}

import { Controller } from "@hotwired/stimulus"

// Keeps the latest line in view while a reply is being written, unless the reader scrolled up to read.
export default class extends Controller {
  connect() {
    this.follow = true
    this.onScroll = () => {
      const gap = document.documentElement.scrollHeight - window.scrollY - window.innerHeight
      this.follow = gap < 160
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.observer = new MutationObserver(() => {
      if (this.follow) window.scrollTo({ top: document.documentElement.scrollHeight })
    })
    this.observer.observe(this.element, { childList: true, subtree: true, characterData: true })
    window.scrollTo({ top: document.documentElement.scrollHeight })
  }

  disconnect() {
    this.observer.disconnect()
    window.removeEventListener("scroll", this.onScroll)
  }
}

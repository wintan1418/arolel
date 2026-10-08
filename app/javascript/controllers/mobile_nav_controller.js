import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "toggle"]

  connect() {
    this.element.dataset.mobileNavReady = "true"
    this.boundResize = this.handleResize.bind(this)
    window.addEventListener("resize", this.boundResize)
    this.close()
  }

  disconnect() {
    window.removeEventListener("resize", this.boundResize)
    delete this.element.dataset.mobileNavReady
  }

  toggle() {
    if (this.panelTarget.hidden) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.panelTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.toggleTarget.setAttribute("aria-label", "Close navigation")
    this.element.classList.add("is-mobile-open")
    // Move focus into the menu so keyboard and screen-reader users land on it.
    const first = this.panelTarget.querySelector("a, button")
    if (first) first.focus({ preventScroll: true })
  }

  // Close when the user taps or clicks anywhere outside the header.
  outside(event) {
    if (!this.hasPanelTarget || this.panelTarget.hidden) return
    if (this.element.contains(event.target)) return
    this.close()
  }

  close() {
    if (this.hasPanelTarget) {
      this.panelTarget.hidden = true
    }
    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", "false")
      this.toggleTarget.setAttribute("aria-label", "Open navigation")
    }
    this.element.classList.remove("is-mobile-open")
  }

  handleResize() {
    if (window.innerWidth > 1100) {
      this.close()
    }
  }
}

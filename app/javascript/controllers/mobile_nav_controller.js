import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "toggle"]

  connect() {
    this.boundResize = this.handleResize.bind(this)
    window.addEventListener("resize", this.boundResize)
    this.close()
  }

  disconnect() {
    window.removeEventListener("resize", this.boundResize)
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
    this.element.classList.add("is-mobile-open")
  }

  close() {
    if (this.hasPanelTarget) {
      this.panelTarget.hidden = true
    }
    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", "false")
    }
    this.element.classList.remove("is-mobile-open")
  }

  handleResize() {
    if (window.innerWidth > 800) {
      this.close()
    }
  }
}

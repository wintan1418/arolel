import { Controller } from "@hotwired/stimulus"

const DISMISSED_KEY = "arolel-signup-nudge-dismissed-at"
const DISMISS_DAYS = 7
const DELAY_MS = 30000

export default class extends Controller {
  static targets = ["panel"]

  connect () {
    if (this.recentlyDismissed()) return

    this.started = false
    this.boundStart = this.startTimer.bind(this)
    window.addEventListener("scroll", this.boundStart, { passive: true })
  }

  disconnect () {
    window.removeEventListener("scroll", this.boundStart)
    clearTimeout(this.timer)
  }

  startTimer () {
    if (this.started || window.scrollY < 80) return

    this.started = true
    window.removeEventListener("scroll", this.boundStart)
    this.timer = setTimeout(() => this.open(), DELAY_MS)
  }

  open () {
    if (this.recentlyDismissed()) return

    this.element.hidden = false
    requestAnimationFrame(() => this.element.classList.add("is-open"))
  }

  close () {
    this.dismiss()
  }

  dismiss () {
    localStorage.setItem(DISMISSED_KEY, Date.now().toString())
    this.element.classList.remove("is-open")
    setTimeout(() => {
      this.element.hidden = true
    }, 180)
  }

  backdrop (event) {
    if (event.target === this.element) this.dismiss()
  }

  recentlyDismissed () {
    const dismissedAt = parseInt(localStorage.getItem(DISMISSED_KEY) || "0", 10)
    if (!dismissedAt) return false

    return Date.now() - dismissedAt < DISMISS_DAYS * 24 * 60 * 60 * 1000
  }
}

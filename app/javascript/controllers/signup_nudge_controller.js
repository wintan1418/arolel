import { Controller } from "@hotwired/stimulus"

const DISMISSED_KEY = "arolel-signup-nudge-dismissed-at"
const DISMISS_DAYS = 7
const DELAY_MS = 45000

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
    // Never interrupt a conversion or a download in progress.
    if (window.__arolelUnsavedWork && [...window.__arolelUnsavedWork].some((check) => { try { return check() } catch (_) { return false } })) {
      this.timer = setTimeout(() => this.open(), DELAY_MS)
      return
    }

    this.previousFocus = document.activeElement
    this.element.hidden = false
    requestAnimationFrame(() => {
      this.element.classList.add("is-open")
      const first = this.panelTarget.querySelector("a, button")
      if (first) first.focus()
    })
  }

  escape () {
    if (!this.element.hidden) this.dismiss()
  }

  close () {
    this.dismiss()
  }

  dismiss () {
    try { localStorage.setItem(DISMISSED_KEY, Date.now().toString()) } catch (_) {}
    this.element.classList.remove("is-open")
    setTimeout(() => {
      this.element.hidden = true
    }, 180)
    if (this.previousFocus && typeof this.previousFocus.focus === "function") this.previousFocus.focus()
  }

  backdrop (event) {
    if (event.target === this.element) this.dismiss()
  }

  recentlyDismissed () {
    let dismissedAt = 0
    try { dismissedAt = parseInt(localStorage.getItem(DISMISSED_KEY) || "0", 10) } catch (_) {}
    if (!dismissedAt) return false

    return Date.now() - dismissedAt < DISMISS_DAYS * 24 * 60 * 60 * 1000
  }
}

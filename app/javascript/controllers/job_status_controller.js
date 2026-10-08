import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Polls a job's JSON status and updates the progress bar in place. When the
// job finishes it reloads the page once so the download button appears,
// instead of refreshing the whole page every few seconds while waiting.
export default class extends Controller {
  static targets = ["percent", "fill", "bar", "message"]
  static values = { url: String, active: Boolean, interval: { type: Number, default: 5000 } }

  connect () {
    if (this.activeValue) this.schedule()
  }

  disconnect () {
    clearTimeout(this.timer)
  }

  schedule () {
    this.timer = setTimeout(() => this.poll(), this.intervalValue)
  }

  async poll () {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (res.status === 404 || res.redirected) { Turbo.visit(window.location.href, { action: "replace" }); return }
      if (!res.ok) { this.schedule(); return }
      const data = await res.json()
      this.render(data)
      if (data.active) {
        this.schedule()
      } else {
        Turbo.visit(window.location.href, { action: "replace" })
      }
    } catch (_) {
      this.schedule()
    }
  }

  render (data) {
    const pct = Math.max(0, Math.min(100, Number(data.progress) || 0))
    if (this.hasPercentTarget) this.percentTarget.textContent = pct
    if (this.hasFillTarget) this.fillTarget.style.width = `${Math.max(pct, data.active ? 4 : 0)}%`
    if (this.hasBarTarget) this.barTarget.setAttribute("aria-valuenow", pct)
    if (this.hasMessageTarget && data.message) this.messageTarget.textContent = data.message
  }
}

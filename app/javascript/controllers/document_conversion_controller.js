import { Controller } from "@hotwired/stimulus"

const MAX_BYTES = 25 * 1024 * 1024

export default class extends Controller {
  static targets = ["file", "submit", "status", "details"]
  static values = { op: String }

  connect () {
    this.defaultLabel = this.submitTarget.value
  }

  picked () {
    const file = this.fileTarget.files[0]
    if (!file) {
      this.statusTarget.textContent = "Choose a file to convert."
      this.detailsTarget.textContent = ""
      this.submitTarget.disabled = true
      return
    }

    const size = this.formatBytes(file.size)
    this.statusTarget.textContent = `${file.name} · ${size}`
    this.submitTarget.disabled = file.size > MAX_BYTES

    if (file.size > MAX_BYTES) {
      this.detailsTarget.textContent = "This file is over 25MB. Choose a smaller file before uploading."
      return
    }

    this.detailsTarget.textContent = this.pdfOperation()
      ? "Checking page count before upload..."
      : "Ready. The file will upload temporarily for conversion."

    if (this.pdfOperation()) this.estimatePdfPages(file)
  }

  submitting (event) {
    const file = this.fileTarget.files[0]
    if (!file || file.size > MAX_BYTES) {
      event.preventDefault()
      return
    }

    this.submitTarget.disabled = true
    this.submitTarget.value = "Uploading..."
    this.statusTarget.textContent = "Uploading file..."
    this.detailsTarget.textContent = "Converting after upload. Your download will start when the server finishes."
  }

  async estimatePdfPages (file) {
    if (!/\.pdf$/i.test(file.name)) {
      this.detailsTarget.textContent = "Ready. The file will upload temporarily for conversion."
      return
    }

    try {
      const bytes = await file.arrayBuffer()
      const text = new TextDecoder("latin1").decode(bytes)
      const pages = (text.match(/\/Type\s*\/Page\b/g) || []).length

      if (pages > 0) {
        const cap = this.imageOperation() ? " · first 50 pages will be rendered" : ""
        this.detailsTarget.textContent = `${pages} estimated page${pages === 1 ? "" : "s"}${cap}.`
      } else {
        this.detailsTarget.textContent = "Ready. Page count will be checked on the server."
      }
    } catch {
      this.detailsTarget.textContent = "Ready. Page count will be checked on the server."
    }
  }

  pdfOperation () {
    return this.opValue.startsWith("pdf-to-")
  }

  imageOperation () {
    return this.opValue === "pdf-to-jpg" || this.opValue === "pdf-to-png"
  }

  formatBytes (bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  }
}

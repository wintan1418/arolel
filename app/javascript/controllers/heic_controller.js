import { Controller } from "@hotwired/stimulus"
import heic2any from "heic2any"
import { zip } from "fflate"
import { guardUnsavedWork } from "../lib/unsaved_work"
import { pressTab } from "../lib/tabs"
import { describeRejected, showDropError } from "../lib/drop_errors"

// HEIC → JPG/PNG/WebP. All in-browser. Queues files and processes sequentially
// (heic2any itself is heavy; parallelism doesn't help much on a single core).
export default class extends Controller {
  static targets = [
    "drop", "input", "options", "list", "zipBtn", "convertBtn", "dropError",
    "quality", "format",
    "bytesSent", "threads", "queued", "done"
  ]

  connect () {
    this.files = []  // { id, file, name, size, status, outSize, outBlob, ext }
    this.quality = 0.9
    this.format  = "image/jpeg"
    this.processing = false
    this.started = false    // nothing converts until the user hits Convert
    this.generation = 0     // bumped when settings change mid-flight
    this.exported = false
    if (this.hasThreadsTarget) this.threadsTarget.textContent = "1"
    this.unguard = guardUnsavedWork(() => this.files.length > 0 && !this.exported)
  }

  disconnect () {
    if (this.unguard) this.unguard()
  }

  pick (e) {
    if (e && e.type === "keydown") e.preventDefault()
    this.inputTarget.click()
  }

  picked (e) { this.addFiles(Array.from(e.target.files || [])); e.target.value = "" }

  drop (e) {
    e.preventDefault()
    if (this.hasDropTarget) this.dropTarget.classList.remove("is-active")
    const items = (e.dataTransfer && e.dataTransfer.files) || []
    this.addFiles(Array.from(items))
  }

  addFiles (files) {
    const isHeic = (f) => /\.(heic|heif)$/i.test(f.name) || /heic|heif/i.test(f.type)
    const heic = files.filter(isHeic)
    const rejected = files.filter((f) => !isHeic(f))
    showDropError(this.hasDropErrorTarget && this.dropErrorTarget, describeRejected(rejected, "a HEIC photo", "This tool accepts .heic and .heif. For JPG, PNG or WebP use the Images tool."))
    if (heic.length === 0) return
    this.exported = false
    for (const f of heic) {
      this.files.push({
        id: crypto.randomUUID(),
        file: f,
        name: f.name,
        size: f.size,
        status: "queue",
        outSize: null,
        outBlob: null,
        ext: null
      })
    }
    this.render()
    this.updateConvertBtn()
    if (this.started) this.processNext()
  }

  setQuality (e) {
    this.quality = parseFloat(e.currentTarget.dataset.q)
    this.selectTab(this.qualityTarget, e.currentTarget)
    this.settingsChanged()
  }

  setFormat (e) {
    this.format = e.currentTarget.dataset.f
    this.selectTab(this.formatTarget, e.currentTarget)
    this.settingsChanged()
  }

  selectTab (group, active) {
    pressTab(group, active)
  }

  // Once conversion has started, any settings change reprocesses everything
  // so the downloads always reflect the current settings.
  settingsChanged () {
    if (this.started) this.reprocess()
  }

  start () {
    if (this.files.length === 0) {
      this.pick()
      return
    }
    if (this.started) { this.reprocess(); return }
    this.started = true
    this.updateConvertBtn()
    this.processNext()
  }

  // Re-convert all files with the current settings.
  reprocess () {
    this.generation++
    this.exported = false
    this.files.forEach((f) => {
      f.status = "queue"
      f.outBlob = null
      f.outSize = null
      f.ext = null
    })
    this.updateZipBtn()
    this.render()
    this.processNext()
  }

  clear () {
    this.files = []
    this.started = false
    this.generation++
    this.render()
    this.listTarget.style.display = "none"
    this.zipBtnTarget.disabled = true
    this.updateConvertBtn()
  }

  updateConvertBtn () {
    if (!this.hasConvertBtnTarget) return
    const count = this.files.length
    if (count === 0) {
      this.convertBtnTarget.textContent = "Convert"
      this.convertBtnTarget.disabled = true
      return
    }
    this.convertBtnTarget.disabled = false
    this.convertBtnTarget.textContent = this.started
      ? "Convert again"
      : `Convert ${count} ${count === 1 ? "photo" : "photos"}`
  }

  async processNext () {
    if (this.processing || !this.started) return
    const next = this.files.find((f) => f.status === "queue")
    if (!next) return
    this.processing = true
    const gen = this.generation
    next.status = "work"
    this.render()

    try {
      const result = await heic2any({
        blob: next.file,
        toType: this.format,
        quality: this.quality
      })
      const blob = Array.isArray(result) ? result[0] : result
      if (gen === this.generation) {
        next.outBlob = blob
        next.outSize = blob.size
        next.ext = this.format === "image/jpeg" ? "jpg" :
                   this.format === "image/png"  ? "png" : "webp"
        next.status = "done"
      } else if (next.status === "work") {
        // Settings changed while this file was in flight — result is stale.
        next.status = "queue"
      }
    } catch (err) {
      console.error(err)
      next.status = gen === this.generation ? "error" : "queue"
    }
    this.processing = false
    this.render()
    this.updateZipBtn()
    this.processNext()
  }

  updateZipBtn () {
    const anyDone = this.files.some((f) => f.status === "done")
    this.zipBtnTarget.disabled = !anyDone
  }

  async downloadZip () {
    const done = this.files.filter((f) => f.status === "done")
    if (done.length === 0) return
    this.exported = true
    if (done.length === 1) {
      this.triggerDownload(done[0].outBlob, this.renameFile(done[0].name, done[0].ext))
      return
    }
    const buffers = {}
    for (const f of done) {
      const buf = new Uint8Array(await f.outBlob.arrayBuffer())
      buffers[this.renameFile(f.name, f.ext)] = [buf, { level: 0 }]
    }
    zip(buffers, { level: 0 }, (err, data) => {
      if (err) { console.error(err); return }
      const blob = new Blob([data], { type: "application/zip" })
      this.triggerDownload(blob, "heic-converted.zip")
    })
  }

  downloadOne (e) {
    const id = e.currentTarget.dataset.id
    const f = this.files.find((x) => x.id === id)
    if (!f || !f.outBlob) return
    this.exported = true
    this.triggerDownload(f.outBlob, this.renameFile(f.name, f.ext))
  }

  removeOne (e) {
    const id = e.currentTarget.dataset.id
    this.files = this.files.filter((f) => f.id !== id)
    if (this.files.length === 0) {
      this.clear()
    } else {
      this.render()
      this.updateZipBtn()
      this.updateConvertBtn()
    }
  }

  triggerDownload (blob, name) {
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = name
    document.body.appendChild(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }

  renameFile (name, ext) {
    return name.replace(/\.(heic|heif)$/i, `.${ext}`)
  }

  render () {
    if (this.files.length === 0) {
      this.listTarget.style.display = "none"
      this.listTarget.innerHTML = ""
      return
    }
    this.listTarget.style.display = "block"
    this.listTarget.innerHTML = this.files.map((f) => this.rowHtml(f)).join("")
    // wire per-row buttons
    this.listTarget.querySelectorAll("[data-action-dl]").forEach((btn) =>
      btn.addEventListener("click", (e) => this.downloadOne({ currentTarget: e.currentTarget })))
    this.listTarget.querySelectorAll("[data-action-rm]").forEach((btn) =>
      btn.addEventListener("click", (e) => this.removeOne({ currentTarget: e.currentTarget })))
    // counts
    if (this.hasQueuedTarget) this.queuedTarget.textContent = this.files.filter((f) => f.status === "queue" || f.status === "work").length
    if (this.hasDoneTarget)   this.doneTarget.textContent   = this.files.filter((f) => f.status === "done").length
  }

  rowHtml (f) {
    const meta = `${this.fmtBytes(f.size)}${f.outSize ? ` → ${this.fmtBytes(f.outSize)}` : ""}`
    let status = ""
    let action = ""
    if (f.status === "queue") {
      status = `<span class="tb-pill tb-pill-neu">${this.started ? "queued" : "ready"}</span>`
      action = `<button class="tb-btn tb-btn-quiet" data-action-rm data-id="${f.id}">remove</button>`
    } else if (f.status === "work") {
      status = `<div class="tb-progress"><div class="tb-progress-fill" style="width: 70%"></div></div>`
      action = `<span class="tb-mono tb-muted" style="font-size:11px;">working…</span>`
    } else if (f.status === "done") {
      status = `<span class="tb-pill tb-pill-ok">done</span>`
      action = `<button class="tb-btn tb-btn-ghost" data-action-dl data-id="${f.id}" style="height:30px;padding:0 10px;font-size:12px;">download</button>`
    } else {
      status = `<span class="tb-pill tb-pill-down">failed</span>`
      action = `<button class="tb-btn tb-btn-quiet" data-action-rm data-id="${f.id}">remove</button>`
    }
    return `
      <div class="tb-file-row">
        <span class="tb-file-thumb" aria-hidden="true">HEIC</span>
        <div class="tb-file-main">
          <div class="tb-file-name">${this.escape(f.name)}</div>
          <div class="tb-file-meta">${meta}</div>
        </div>
        <div class="tb-file-status">${status}</div>
        <div class="tb-file-where tb-mono tb-muted" style="font-size:11px;">local</div>
        <div class="tb-file-actions">${action}</div>
      </div>
    `
  }

  fmtBytes (n) {
    if (n == null) return ""
    if (n < 1024) return `${n} B`
    if (n < 1024 * 1024) return `${(n/1024).toFixed(1)} KB`
    return `${(n/1024/1024).toFixed(1)} MB`
  }

  escape (s) {
    return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }
}

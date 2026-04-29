import { Controller } from "@hotwired/stimulus"
// NOTE: we do not import @ffmpeg/ffmpeg statically — it's a big dependency
// (~3MB JS wrapper + ~25MB WASM core) and we want to keep the rest of the
// site snappy. It's lazy-loaded when the user drops their first file.

// Served from our own origin — no CDN hangs, no cross-origin rules to fight.
// See /public/vendor/ffmpeg/{mt,st}/ for the actual binaries.
const FFMPEG_MT_BASE = "/vendor/ffmpeg/mt"
const FFMPEG_ST_BASE = "/vendor/ffmpeg/st"
const FFMPEG_WRAPPER_URL = "/vendor/ffmpeg/pkg/ffmpeg.js"
const FFMPEG_LOAD_TIMEOUT_MS = 120_000
const FFMPEG_USE_MULTI_THREAD = false

export default class extends Controller {
  static targets = [
    "drop", "input", "list",
    "ffmpegStatus", "ffmpegStatusText",
    "queued", "done"
  ]
  static values = { op: String, extIn: String, extOut: String }

  connect () {
    this.files = []
    this.ffmpeg = null
    this.ffmpegLoading = null
    this.ffmpegWrapperLoading = null
    this.processing = false

    // Pre-fetch ffmpeg.wasm so it's usually ready by the time the user drops
    // a file. Runs in the background.
    this.ensureFFmpeg().catch((err) => {
      console.warn("[media] pre-load failed:", err)
      this.statusText(`error loading FFmpeg: ${err.message}`)
    })
  }

  pick () { this.inputTarget.click() }
  picked (e) { this.addFiles(Array.from(e.target.files || [])) }

  drop (e) {
    e.preventDefault()
    if (this.hasDropTarget) this.dropTarget.classList.remove("is-active")
    this.addFiles(Array.from((e.dataTransfer && e.dataTransfer.files) || []))
  }

  addFiles (files) {
    const accept = this.extInValue === "mp4"
      ? /\.(mp4|m4a|mov)$/i
      : /\.webm$/i
    const filtered = files.filter((f) => accept.test(f.name))

    if (files.length > 0 && filtered.length === 0) {
      this.toast(`Only ${this.extInValue.toUpperCase()} files supported on this page.`)
      return
    }
    if (filtered.length === 0) return

    for (const f of filtered) {
      this.files.push({
        id: crypto.randomUUID(),
        file: f,
        name: f.name,
        size: f.size,
        status: "queue",
        progress: 0,
        outBlob: null,
        outSize: null,
        error: null
      })
    }
    // Show the status card immediately so users see *something* while ffmpeg loads.
    if (this.hasFfmpegStatusTarget) this.ffmpegStatusTarget.style.display = "block"
    this.statusText("preparing…")
    this.render()
    this.processNext()
  }

  clear () {
    this.files = []
    this.render()
  }

  // ----- lazy ffmpeg load -----

  async ensureFFmpeg () {
    if (this.ffmpeg)        return this.ffmpeg
    if (this.ffmpegLoading) return this.ffmpegLoading   // in-flight load, share it

    this.ffmpegLoading = this._loadFFmpeg()
    try {
      return await this.ffmpegLoading
    } finally {
      this.ffmpegLoading = null
    }
  }

  async _loadFFmpeg () {
    this.ffmpegStatusTarget.style.display = "block"
    this.debug("connect-load", { op: this.opValue })

    // Multi-threaded ffmpeg needs SharedArrayBuffer and COOP/COEP. Those
    // headers made Chromium hang during runtime startup here, so keep the
    // reliable single-threaded path unless FFMPEG_USE_MULTI_THREAD is enabled.
    const hasSAB = typeof SharedArrayBuffer !== "undefined"
    const isolated = self.crossOriginIsolated === true
    const mtAvailable = FFMPEG_USE_MULTI_THREAD && hasSAB && isolated
    console.log("[media] SAB:", hasSAB, "crossOriginIsolated:", isolated, "→ mt:", mtAvailable)
    this.debug("runtime-capabilities", { hasSAB, isolated, mtAvailable })

    const attempts = mtAvailable
      ? [
          { base: FFMPEG_MT_BASE, label: "multi-threaded", worker: true },
          { base: FFMPEG_ST_BASE, label: "single-threaded fallback", worker: false }
        ]
      : [{ base: FFMPEG_ST_BASE, label: "single-threaded", worker: false }]

    let lastError = null
    for (const attempt of attempts) {
      try {
        const ff = await this.loadFFmpegAttempt(attempt)
        this.ffmpeg = ff
        this.mtActive = attempt.worker
        this.statusText(`ready · ${attempt.label}. cached in your browser for next time.`)
        return ff
      } catch (err) {
        lastError = err
        console.warn(`[media] ${attempt.label} runtime failed:`, err)
        this.statusText(`${attempt.label} failed: ${err.message}`)
      }
    }

    throw lastError || new Error("FFmpeg runtime failed to load")
  }

  async loadFFmpegAttempt ({ base, label, worker }) {
    this.statusText(`loading ${label} FFmpeg wrapper…`)
    this.debug("runtime-attempt", { label, worker })
    const { FFmpeg } = await this.loadFFmpegWrapper()
    const ff = new FFmpeg()
    this.attachFFmpegLogHandler(ff)

    const coreURL = new URL(`${base}/ffmpeg-core.js`, location.origin).href
    const wasmURL = new URL(`${base}/ffmpeg-core.wasm`, location.origin).href
    const workerURL = worker ? new URL(`${base}/ffmpeg-core.worker.js`, location.origin).href : null
    this.statusText(`loading ${label} runtime files…`)
    this.debug("runtime-files", { label, coreURL, wasmURL, workerURL })

    let secs = 0
    const tickTimer = setInterval(() => {
      secs += 1
      const msg = secs < 10
        ? `compiling ${label} WebAssembly… ${secs}s`
        : secs < 20
          ? `compiling (this takes 15–30s first time)… ${secs}s`
          : secs < 45
            ? `almost there… ${secs}s`
            : `still working at ${secs}s — trying a fallback if this times out.`
      this.statusText(msg)
    }, 1000)

    const loadOpts = { coreURL, wasmURL }
    if (workerURL) loadOpts.workerURL = workerURL
    try {
      await this.withTimeout(ff.load(loadOpts), FFMPEG_LOAD_TIMEOUT_MS, `${label} FFmpeg runtime initialisation timed out`)
      this.debug("runtime-ready", { label })
    } catch (err) {
      try { ff.terminate() } catch (_) {}
      this.debug("runtime-error", { label, message: err.message })
      throw err
    } finally {
      clearInterval(tickTimer)
    }

    return ff
  }

  attachFFmpegLogHandler (ff) {
    ff.on("log", ({ message }) => {
      const m = /time=(\d+):(\d+):([\d.]+)/.exec(message)
      if (m && this.currentFile) {
        const seconds = (+m[1]) * 3600 + (+m[2]) * 60 + parseFloat(m[3])
        this.currentFile.progress = Math.min(99, Math.max(1, Math.round((seconds / (this.currentFile.durationHint || 60)) * 100)))
        this.renderRow(this.currentFile)
      }
    })
  }

  loadFFmpegWrapper () {
    if (window.FFmpegWASM) return Promise.resolve(window.FFmpegWASM)
    if (this.ffmpegWrapperLoading) return this.ffmpegWrapperLoading

    this.ffmpegWrapperLoading = new Promise((resolve, reject) => {
      const existing = document.querySelector(`script[src="${FFMPEG_WRAPPER_URL}"]`)
      if (existing) {
        existing.addEventListener("load", () => resolve(window.FFmpegWASM), { once: true })
        existing.addEventListener("error", () => reject(new Error(`failed to load ${FFMPEG_WRAPPER_URL}`)), { once: true })
        return
      }

      const script = document.createElement("script")
      script.src = FFMPEG_WRAPPER_URL
      script.async = true
      this.debug("wrapper-load", { url: FFMPEG_WRAPPER_URL })
      script.onload = () => {
        if (window.FFmpegWASM) {
          this.debug("wrapper-ready", { url: FFMPEG_WRAPPER_URL })
          resolve(window.FFmpegWASM)
        } else {
          reject(new Error("FFmpeg wrapper loaded but did not expose window.FFmpegWASM"))
        }
      }
      script.onerror = () => {
        this.debug("wrapper-error", { url: FFMPEG_WRAPPER_URL })
        reject(new Error(`failed to load ${FFMPEG_WRAPPER_URL}`))
      }
      document.head.appendChild(script)
    }).finally(() => {
      this.ffmpegWrapperLoading = null
    })

    return this.ffmpegWrapperLoading
  }

  async fetchFile (file) {
    return new Uint8Array(await file.arrayBuffer())
  }

  withTimeout (promise, ms, message) {
    let timer
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${message} after ${Math.round(ms / 1000)}s`)), ms)
    })
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer))
  }

  debug (event, data = {}) {
    if (!["localhost", "127.0.0.1"].includes(location.hostname)) return
    const payload = new URLSearchParams({
      event,
      data: JSON.stringify(data),
      at: String(Date.now())
    })
    fetch(`/media-debug?${payload.toString()}`, { keepalive: true }).catch(() => {})
  }

  statusProgress (label, got, total) {
    if (!this.hasFfmpegStatusTextTarget) return
    const pct = total ? Math.round((got / total) * 100) : null
    const bar = total
      ? `<div class="tb-progress" style="margin-top:8px"><div class="tb-progress-fill" style="width:${pct}%"></div></div>
         <div class="tb-mono tb-muted" style="font-size:11px;margin-top:4px">${this.fmtBytes(got)} / ${this.fmtBytes(total)} · ${pct}%</div>`
      : `<div class="tb-mono tb-muted" style="font-size:11px;margin-top:4px">${this.fmtBytes(got)} downloaded…</div>`
    this.ffmpegStatusTextTarget.innerHTML = `${label}${bar}`
  }

  statusText (msg) {
    if (this.hasFfmpegStatusTextTarget) this.ffmpegStatusTextTarget.textContent = msg
  }

  // ----- processing -----

  async processNext () {
    if (this.processing) return
    const next = this.files.find((f) => f.status === "queue")
    if (!next) return

    this.processing = true
    // Keep `status = "queue"` until ffmpeg is actually ready — otherwise the
    // UI shows "0% conversion" while really ffmpeg is still downloading.
    this.currentFile = next
    this.renderRow(next)

    try {
      const ff = await this.ensureFFmpeg()

      // Now it's real work.
      next.status = "work"
      this.renderRow(next)

      // Best-effort duration guess from the file — used for % progress only.
      next.durationHint = await this.guessDuration(next.file).catch(() => null)

      const inputName  = `in.${this.extInValue}`
      const outputName = `out.${this.extOutValue}`

      await ff.writeFile(inputName, await this.fetchFile(next.file))

      const args = this.ffmpegArgs(inputName, outputName)
      const exitCode = await ff.exec(args)
      if (exitCode !== 0) throw new Error(`FFmpeg exited with code ${exitCode}`)

      const outData = await ff.readFile(outputName)
      const mime = this.extOutValue === "mp3" ? "audio/mpeg" : "video/mp4"
      const blob = new Blob([outData.buffer], { type: mime })

      next.outBlob = blob
      next.outSize = blob.size
      next.progress = 100
      next.status = "done"

      // Free ffmpeg's virtual filesystem so long sessions don't balloon.
      try { await ff.deleteFile(inputName) } catch (_) {}
      try { await ff.deleteFile(outputName) } catch (_) {}
    } catch (err) {
      console.error("[media]", err)
      next.error = (err && err.message) || "failed"
      next.status = "error"
      this.statusText(`error: ${next.error}`)
      this.toast(`Conversion failed: ${next.error.slice(0, 140)}`)
    }

    this.currentFile = null
    this.processing = false
    this.renderRow(next)
    this.updateCounts()
    this.processNext()
  }

  toast (msg) {
    const t = document.createElement("div")
    t.className = "tb-toast"; t.textContent = msg
    document.body.appendChild(t); setTimeout(() => t.remove(), 5000)
  }

  ffmpegArgs (input, output) {
    if (this.opValue === "mp4-to-mp3") {
      // Strip video, re-encode audio as 192 kbps MP3.
      return ["-i", input, "-vn", "-acodec", "libmp3lame", "-b:a", "192k", output]
    }
    // WebM → MP4: H.264 video + AAC audio. Real browser/screen recordings can
    // have odd dimensions or alpha-capable pixel formats; normalize them for
    // reliable H.264/browser playback.
    return [
      "-i", input,
      "-map", "0:v:0", "-map", "0:a:0?",
      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p",
      "-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
      "-c:a", "aac", "-b:a", "160k",
      "-sn", "-dn",
      "-movflags", "+faststart",
      output
    ]
  }

  // Read a few metadata bytes off the file to estimate duration for the
  // progress bar. Best-effort; fallback is a crude 60s guess.
  guessDuration (file) {
    return new Promise((resolve) => {
      const url = URL.createObjectURL(file)
      const v = document.createElement("video")
      v.preload = "metadata"
      v.muted = true
      v.onloadedmetadata = () => {
        const d = v.duration || 60
        URL.revokeObjectURL(url)
        resolve(isFinite(d) ? d : 60)
      }
      v.onerror = () => { URL.revokeObjectURL(url); resolve(60) }
      v.src = url
    })
  }

  // ----- downloads + row actions -----

  downloadOne (e) {
    const f = this.files.find((x) => x.id === e.currentTarget.dataset.id)
    if (!f || !f.outBlob) return
    const name = f.name.replace(/\.[^.]+$/, `.${this.extOutValue}`)
    this.triggerDownload(f.outBlob, name)
  }

  removeOne (e) {
    this.files = this.files.filter((f) => f.id !== e.currentTarget.dataset.id)
    this.render()
  }

  triggerDownload (blob, name) {
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url; a.download = name
    document.body.appendChild(a); a.click(); a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }

  // ----- render -----

  render () {
    if (this.files.length === 0) {
      this.listTarget.style.display = "none"
      this.listTarget.innerHTML = ""
      this.updateCounts()
      return
    }
    this.listTarget.style.display = "block"
    this.listTarget.innerHTML = this.files.map((f) => this.rowHtml(f)).join("")
    this.wireRowButtons()
    this.updateCounts()
  }

  renderRow (f) {
    const row = this.listTarget.querySelector(`[data-row="${f.id}"]`)
    if (!row) return this.render()
    row.outerHTML = this.rowHtml(f)
    this.wireRowButtons()
    this.updateCounts()
  }

  wireRowButtons () {
    this.listTarget.querySelectorAll("[data-action-dl]").forEach((btn) =>
      btn.addEventListener("click", (e) => this.downloadOne({ currentTarget: e.currentTarget })))
    this.listTarget.querySelectorAll("[data-action-rm]").forEach((btn) =>
      btn.addEventListener("click", (e) => this.removeOne({ currentTarget: e.currentTarget })))
  }

  rowHtml (f) {
    const typeLabel = this.extInValue.toUpperCase()
    const meta = f.outSize != null
      ? `${this.fmtBytes(f.size)} → ${this.fmtBytes(f.outSize)}`
      : this.fmtBytes(f.size)

    let status, action
    if (f.status === "queue") {
      const queueLabel = this.ffmpeg ? "queued" : "waiting for runtime…"
      status = `<span class="tb-pill tb-pill-neu">${queueLabel}</span>`
      action = `<button class="tb-btn tb-btn-quiet" data-action-rm data-id="${f.id}">remove</button>`
    } else if (f.status === "work") {
      status = `<div class="tb-progress"><div class="tb-progress-fill" style="width: ${f.progress || 2}%"></div></div>`
      action = `<span class="tb-mono tb-muted" style="font-size:11px;">${f.progress || 0}%</span>`
    } else if (f.status === "done") {
      status = `<span class="tb-pill tb-pill-ok">done</span>`
      action = `<button class="tb-btn tb-btn-ghost" data-action-dl data-id="${f.id}" style="height:30px;padding:0 10px;font-size:12px;">download</button>`
    } else {
      status = `<span class="tb-pill tb-pill-down">failed</span>`
      action = `<button class="tb-btn tb-btn-quiet" data-action-rm data-id="${f.id}">remove</button>`
    }

    return `
      <div class="tb-file-row" data-row="${f.id}">
        <span class="tb-file-thumb">${typeLabel}</span>
        <div>
          <div class="tb-file-name">${this.escape(f.name)}</div>
          <div class="tb-file-meta">${meta}</div>
        </div>
        <div>${status}</div>
        <div class="tb-mono tb-muted" style="font-size:11px;">local</div>
        <div style="text-align:right;">${action}</div>
      </div>
    `
  }

  updateCounts () {
    if (this.hasQueuedTarget) this.queuedTarget.textContent = this.files.filter((f) => f.status === "queue" || f.status === "work").length
    if (this.hasDoneTarget)   this.doneTarget.textContent   = this.files.filter((f) => f.status === "done").length
  }

  // ----- util -----

  fmtBytes (n) {
    if (n == null) return ""
    if (n < 1024) return `${n} B`
    if (n < 1024 * 1024) return `${(n/1024).toFixed(1)} KB`
    if (n < 1024 * 1024 * 1024) return `${(n/1024/1024).toFixed(1)} MB`
    return `${(n/1024/1024/1024).toFixed(2)} GB`
  }

  escape (s) {
    return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }
}

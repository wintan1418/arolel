import { Controller } from "@hotwired/stimulus"
import { PDFDocument } from "pdf-lib"

// Sign PDF — client-side.
// Flow:
//  1) user drops PDF → we render each page to a <canvas> preview at a reasonable width
//  2) user draws / types / uploads a signature → stored as a PNG data-url
//  3) user clicks on a page preview → we place a draggable signature box there
//  4) user clicks "Stamp & download" → pdf-lib embeds the PNG at the corresponding
//     coordinate on the real PDF page, saves the file, triggers download
export default class extends Controller {
  static targets = [
    "drop", "pdfInput", "pagesWrap", "pages",
    "modeTabs", "drawPanel", "typePanel", "uploadPanel",
    "canvas", "inkColor", "typeText", "sigInput", "variants",
    "signaturePreview", "signatureActions", "saveSignatureBtn", "signatureStatus",
    "savedSeed", "savedList", "downloadBtn"
  ]
  static values = {
    signedIn: Boolean,
    loginUrl: String,
    registerUrl: String
  }

  connect () {
    this.pdfBuffer = null
    this.pdfDoc    = null             // pdf-lib doc
    this.pageInfos = []               // { w, h, canvasEl, placements: [ {x,y,w,h} relative to canvas, el } ]
    this.signature = null             // PNG data-url
    this.signatureMeta = null
    this.typedVariants = []
    this.savedSignatures = []
    this.signatureMode = "draw"
    this.drawing   = false
    this.ink       = "#0f172a"
    this.initPad()
    this.loadSavedSignatures()
    this.updateDownloadBtn()
    this.updateSignatureActions()
  }

  // ----- signature pad -----

  initPad () {
    const c = this.canvasTarget
    // Resize canvas backing store to match layout × DPR.
    const fit = () => {
      const dpr = window.devicePixelRatio || 1
      const rect = c.getBoundingClientRect()
      c.width  = Math.floor(rect.width * dpr)
      c.height = Math.floor(rect.height * dpr)
      const ctx = c.getContext("2d")
      ctx.scale(dpr, dpr)
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      ctx.lineWidth = 2.2
    }
    fit()
    window.addEventListener("resize", fit)

    const start = (e) => { this.drawing = true; const p = this.padPoint(e); this.lastP = p }
    const move  = (e) => {
      if (!this.drawing) return
      const ctx = c.getContext("2d"); ctx.strokeStyle = this.ink
      const p = this.padPoint(e)
      ctx.beginPath(); ctx.moveTo(this.lastP.x, this.lastP.y); ctx.lineTo(p.x, p.y); ctx.stroke()
      this.lastP = p
    }
    const end   = () => { if (this.drawing) { this.drawing = false; this.captureSigFromCanvas() } }

    c.addEventListener("pointerdown", (e) => { c.setPointerCapture(e.pointerId); start(e) })
    c.addEventListener("pointermove", move)
    c.addEventListener("pointerup",   end)
    c.addEventListener("pointercancel", end)
  }

  padPoint (e) {
    const rect = this.canvasTarget.getBoundingClientRect()
    return { x: e.clientX - rect.left, y: e.clientY - rect.top }
  }

  changeColor () { this.ink = this.inkColorTarget.value }

  clearPad () {
    const c = this.canvasTarget
    c.getContext("2d").clearRect(0, 0, c.width, c.height)
    this.signature = null
    this.signatureMeta = null
    this.updateDownloadBtn()
    this.updateSignatureActions()
    this.updateSignaturePreview()
  }

  captureSigFromCanvas () {
    // Crop to opaque pixels for a tight signature, then export as PNG.
    const signature = this.cropCanvasToPng(this.canvasTarget)
    if (!signature) {
      this.signature = null
      this.signatureMeta = null
      this.updateSignatureActions()
      this.updateSignaturePreview()
      return
    }
    this.setSignature(signature, { name: "Drawn signature", sourceText: "", styleKey: "draw" })
    this.updateDownloadBtn()
  }

  // ----- mode switching -----

  setMode (e) {
    this.signatureMode = e.currentTarget.dataset.mode
    this.modeTabsTarget.querySelectorAll(".tb-tab").forEach((b) => b.classList.remove("is-active"))
    e.currentTarget.classList.add("is-active")
    this.drawPanelTarget.hidden   = this.signatureMode !== "draw"
    this.typePanelTarget.hidden   = this.signatureMode !== "type"
    this.uploadPanelTarget.hidden = this.signatureMode !== "upload"
  }

  typedSig () {
    const text = (this.typeTextTarget.value || "").trim()
    if (!text) {
      this.signature = null
      this.signatureMeta = null
      this.typedVariants = []
      this.variantsTarget.innerHTML = ""
      this.updateDownloadBtn()
      this.updateSignatureActions()
      this.updateSignaturePreview()
      return
    }

    this.renderTypedVariants(text)
    this.updateDownloadBtn()
  }

  renderTypedVariants (text) {
    this.typedVariants = this.signatureStyles().map((style) => ({
      style,
      image: this.renderTypedSignature(text, style)
    }))
    this.variantsTarget.innerHTML = this.typedVariants.map((variant, index) => `
      <button type="button"
              class="tb-tab ${index === 0 ? "is-active" : ""}"
              data-action="click->sign#selectTypedVariant"
              data-sign-index-param="${index}"
              style="height: 62px; padding: 6px; background: var(--tb-paper);">
        <img src="${variant.image}" alt="${this.escape(variant.style.name)}" style="max-height: 44px; width: 100%; object-fit: contain;">
      </button>
    `).join("")
    this.applyTypedVariant(0)
  }

  selectTypedVariant (event) {
    this.applyTypedVariant(event.params.index || 0)
  }

  applyTypedVariant (index) {
    const variant = this.typedVariants[index]
    if (!variant) return

    this.variantsTarget.querySelectorAll(".tb-tab").forEach((button) => button.classList.remove("is-active"))
    const button = this.variantsTarget.querySelector(`[data-sign-index-param="${index}"]`)
    if (button) button.classList.add("is-active")

    this.setSignature(variant.image, {
      name: this.typeTextTarget.value.trim(),
      sourceText: this.typeTextTarget.value.trim(),
      styleKey: variant.style.key
    })
    this.updateDownloadBtn()
  }

  signatureStyles () {
    return [
      { key: "serif-flow", name: "Serif flow", font: "italic 600 64px \"Source Serif 4\", Georgia, serif", rotate: -0.02, scaleX: 1, y: 100 },
      { key: "script-wide", name: "Wide script", font: "italic 500 58px \"Segoe Script\", \"Brush Script MT\", cursive", rotate: -0.04, scaleX: 1.08, y: 104 },
      { key: "classic-ink", name: "Classic ink", font: "italic 600 54px Georgia, \"Times New Roman\", serif", rotate: 0.01, scaleX: 1.14, y: 104, underline: true },
      { key: "compact", name: "Compact", font: "italic 600 48px \"Source Serif 4\", Georgia, serif", rotate: -0.01, scaleX: 0.9, y: 102 },
      { key: "bold-script", name: "Bold script", font: "italic 700 56px \"Segoe Script\", \"Brush Script MT\", cursive", rotate: -0.03, scaleX: 1, y: 104 },
      { key: "formal", name: "Formal", font: "italic 500 52px \"Source Serif 4\", Georgia, serif", rotate: 0, scaleX: 1.04, y: 102, underline: true }
    ]
  }

  renderTypedSignature (text, style) {
    const c = document.createElement("canvas")
    c.width = 760
    c.height = 220
    const ctx = c.getContext("2d")
    ctx.fillStyle = this.ink
    ctx.strokeStyle = this.ink
    ctx.lineCap = "round"
    ctx.lineWidth = 2
    ctx.font = style.font
    ctx.textBaseline = "middle"

    const measured = ctx.measureText(text)
    const maxWidth = 680
    const scale = Math.min(1, maxWidth / Math.max(measured.width, 1))
    ctx.save()
    ctx.translate(36, style.y)
    ctx.rotate(style.rotate || 0)
    ctx.scale((style.scaleX || 1) * scale, scale)
    ctx.fillText(text, 0, 0)
    if (style.underline) {
      const w = Math.min(measured.width, maxWidth)
      ctx.beginPath()
      ctx.moveTo(8, 36)
      ctx.quadraticCurveTo(w * 0.45, 48, w + 24, 34)
      ctx.stroke()
    }
    ctx.restore()

    return this.cropCanvasToPng(c) || c.toDataURL("image/png")
  }

  async uploadedSig () {
    const file = this.sigInputTarget.files[0]
    if (!file) return

    if (!/^image\/(png|jpe?g)$/i.test(file.type) && !/\.(png|jpe?g)$/i.test(file.name)) {
      this.signatureStatusTarget.textContent = "Upload a PNG or JPG signature image."
      return
    }

    const url = URL.createObjectURL(file)
    try {
      const img = await this.loadImage(url)
      const c = document.createElement("canvas")
      const maxW = 520, scale = Math.min(1, maxW / img.width)
      c.width = Math.max(1, Math.round(img.width * scale))
      c.height = Math.max(1, Math.round(img.height * scale))
      c.getContext("2d").drawImage(img, 0, 0, c.width, c.height)
      this.setSignature(c.toDataURL("image/png"), {
        name: file.name.replace(/\.[^.]+$/, ""),
        sourceText: "",
        styleKey: "upload"
      })
      this.signatureStatusTarget.textContent = "uploaded · click a page to place it"
      this.updateDownloadBtn()
    } catch (_) {
      this.signatureStatusTarget.textContent = "Could not read that image. Try a PNG or JPG."
    } finally {
      URL.revokeObjectURL(url)
    }
  }

  setSignature (imageData, meta = {}) {
    this.signature = imageData
    this.signatureMeta = {
      name: meta.name || meta.sourceText || "Signature",
      sourceText: meta.sourceText || "",
      styleKey: meta.styleKey || this.signatureMode
    }
    this.signatureStatusTarget.textContent = ""
    this.updateSignatureActions()
    this.updateSignaturePreview()
  }

  // ----- PDF handling -----

  pick () { this.pdfInputTarget.click() }
  picked (e) { this.loadPdf(e.target.files[0]) }

  drop (e) {
    e.preventDefault()
    if (this.hasDropTarget) this.dropTarget.classList.remove("is-active")
    const f = (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0])
    if (f) this.loadPdf(f)
  }

  async loadPdf (file) {
    if (!file || !/\.pdf$/i.test(file.name)) return
    this.pdfBuffer = await file.arrayBuffer()
    this.pdfDoc = await PDFDocument.load(this.pdfBuffer)

    this.pageInfos = []
    this.pagesWrapTarget.style.display = "block"
    this.pagesTarget.innerHTML = ""

    // For previews we don't need a full raster — pdf-lib can't raster — so we draw a
    // neutral card with the page size ratio and label it. That's enough to let the user
    // place a signature. (For a richer preview we'd need pdf.js; intentionally skipping.)
    const pages = this.pdfDoc.getPages()
    pages.forEach((p, i) => {
      const w = p.getWidth(), h = p.getHeight()
      const container = document.createElement("div")
      container.className = "tb-sign-page"
      container.style.cssText = `position: relative; background: var(--tb-paper); border: 1px solid var(--tb-line-2); border-radius: 6px; width: 100%; aspect-ratio: ${w}/${h}; overflow: hidden; cursor: crosshair;`
      container.innerHTML = `
        <div class="tb-mono" style="position:absolute; top: 8px; left: 10px; font-size: 10px; color: var(--tb-muted);">Page ${i + 1}</div>
        <div class="tb-mono" style="position:absolute; top: 8px; right: 10px; font-size: 10px; color: var(--tb-muted);">${Math.round(w)} × ${Math.round(h)} pt</div>
      `
      container.addEventListener("click", (ev) => this.placeSignatureOn(container, i, ev))
      this.pagesTarget.appendChild(container)
      this.pageInfos.push({ w, h, el: container, placements: [] })
    })

    this.updateDownloadBtn()
  }

  placeSignatureOn (container, pageIdx, ev) {
    if (!this.signature) { this.toast("Draw, type, or upload a signature first."); return }
    const rect = container.getBoundingClientRect()
    const relX = (ev.clientX - rect.left) / rect.width
    const relY = (ev.clientY - rect.top)  / rect.height

    const info = this.pageInfos[pageIdx]
    // default signature box: 160 pt wide, keep aspect
    const sigImg = new Image()
    sigImg.onload = () => {
      const aspect = sigImg.height / sigImg.width
      const sigW = 160 / info.w  // relative width on the page
      const sigH = sigW * aspect * (info.w / info.h)
      const box = this.spawnBox(container, relX - sigW / 2, relY - sigH / 2, sigW, sigH, this.signature)
      info.placements.push(box)
      this.updateDownloadBtn()
    }
    sigImg.src = this.signature
  }

  spawnBox (container, x, y, w, h, imgSrc) {
    const box = document.createElement("div")
    box.className = "tb-sign-box"
    box.style.cssText = `position: absolute; left: ${x * 100}%; top: ${y * 100}%; width: ${w * 100}%; height: ${h * 100}%; background-image: url(${imgSrc}); background-size: contain; background-repeat: no-repeat; background-position: center; border: 1px dashed transparent;`
    const rm = document.createElement("button")
    rm.textContent = "×"; rm.className = "tb-sign-rm"
    rm.style.cssText = "position:absolute; top:-10px; right:-10px; width:20px; height:20px; border-radius:999px; background: var(--tb-ink); color: #fff; border:0; cursor:pointer;"
    box.appendChild(rm)

    box.addEventListener("mouseenter", () => { box.style.border = "1px dashed var(--tb-red)" })
    box.addEventListener("mouseleave", () => { box.style.border = "1px dashed transparent" })

    // Drag
    let dragStart = null
    box.addEventListener("pointerdown", (ev) => {
      if (ev.target === rm) return
      ev.stopPropagation()
      dragStart = { x: ev.clientX, y: ev.clientY, left: parseFloat(box.style.left), top: parseFloat(box.style.top) }
      box.setPointerCapture(ev.pointerId)
    })
    box.addEventListener("pointermove", (ev) => {
      if (!dragStart) return
      const rect = container.getBoundingClientRect()
      const dx = (ev.clientX - dragStart.x) / rect.width  * 100
      const dy = (ev.clientY - dragStart.y) / rect.height * 100
      box.style.left = `${dragStart.left + dx}%`
      box.style.top  = `${dragStart.top + dy}%`
    })
    box.addEventListener("pointerup",   () => { dragStart = null })
    box.addEventListener("pointercancel", () => { dragStart = null })

    rm.addEventListener("click", (ev) => { ev.stopPropagation(); box.remove(); this.updateDownloadBtn() })

    container.appendChild(box)
    return box
  }

  updateDownloadBtn () {
    const any = this.pageInfos.some((p) => p.placements.some((b) => b.isConnected))
    const ready = this.pdfDoc && this.signature && any
    this.downloadBtnTarget.disabled = !ready

    if (ready) {
      this.downloadBtnTarget.textContent = "Stamp & download signed PDF"
    } else if (!this.pdfDoc) {
      this.downloadBtnTarget.textContent = "Choose a PDF first"
    } else if (!this.signature) {
      this.downloadBtnTarget.textContent = "Create a signature first"
    } else {
      this.downloadBtnTarget.textContent = "Click a page to place signature"
    }
  }

  updateSignatureActions () {
    this.signatureActionsTarget.style.display = this.signature ? "flex" : "none"
    if (!this.signature) this.signatureStatusTarget.textContent = ""
  }

  updateSignaturePreview () {
    if (!this.hasSignaturePreviewTarget) return

    if (!this.signature) {
      this.signaturePreviewTarget.innerHTML = `
        <div class="tb-mono tb-muted" style="font-size: 11px;">No signature selected yet.</div>
      `
      return
    }

    this.signaturePreviewTarget.innerHTML = `
      <img src="${this.signature}" alt="${this.escape(this.signatureMeta?.name || "Signature preview")}" style="max-height: 72px; max-width: 100%; object-fit: contain;">
      <div class="tb-mono tb-muted" style="font-size: 11px; margin-top: 6px;">
        ${this.escape(this.signatureMeta?.name || "Signature")} is ready. Click a page preview to place it.
      </div>
    `
  }

  downloadSignature () {
    if (!this.signature) return

    const a = document.createElement("a")
    a.href = this.signature
    a.download = `${this.slugify(this.signatureMeta?.name || "signature")}.png`
    document.body.appendChild(a)
    a.click()
    a.remove()
  }

  async saveSignature () {
    if (!this.signature) {
      this.toast("Create a signature first.")
      return
    }

    if (!this.signedInValue) {
      this.signatureStatusTarget.innerHTML = `
        <a href="${this.escape(this.loginUrlValue)}" style="color: var(--tb-red); text-decoration: underline;">Log in</a>
        or
        <a href="${this.escape(this.registerUrlValue)}" style="color: var(--tb-red); text-decoration: underline;">register</a>
        to save.
      `
      return
    }

    this.saveSignatureBtnTarget.disabled = true
    this.signatureStatusTarget.textContent = "saving..."
    try {
      const res = await fetch("/digital_signatures", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrf(),
          Accept: "application/json"
        },
        body: JSON.stringify({
          digital_signature: {
            name: this.signatureMeta?.name || "Signature",
            source_text: this.signatureMeta?.sourceText || "",
            style_key: this.signatureMeta?.styleKey || "",
            image_data: this.signature
          }
        })
      })

      if (res.status === 401) {
        this.signatureStatusTarget.innerHTML = `
          <a href="${this.escape(this.loginUrlValue)}" style="color: var(--tb-red); text-decoration: underline;">Log in</a>
          or
          <a href="${this.escape(this.registerUrlValue)}" style="color: var(--tb-red); text-decoration: underline;">register</a>
          to save.
        `
        return
      }
      const data = await res.json()
      if (!res.ok) throw new Error((data.errors || ["Could not save signature."]).join(", "))

      this.savedSignatures.unshift(data)
      this.renderSavedSignatures()
      this.signatureStatusTarget.textContent = "saved"
    } catch (err) {
      this.signatureStatusTarget.textContent = err.message || "save failed"
    } finally {
      this.saveSignatureBtnTarget.disabled = false
    }
  }

  async download () {
    if (!this.pdfDoc) return
    // Re-load a fresh copy so repeated downloads don't compound stamps.
    const pdf = await PDFDocument.load(this.pdfBuffer)
    const sigPngBytes = await this.pngDataUrlToBytes(this.signature)
    const sigImg = await pdf.embedPng(sigPngBytes)

    const pages = pdf.getPages()
    for (let i = 0; i < this.pageInfos.length; i++) {
      const info = this.pageInfos[i]
      const page = pages[i]
      const pw = page.getWidth(), ph = page.getHeight()
      for (const box of info.placements) {
        if (!box.isConnected) continue
        const leftPct = parseFloat(box.style.left) / 100
        const topPct  = parseFloat(box.style.top)  / 100
        const widthPct  = parseFloat(box.style.width)  / 100
        const heightPct = parseFloat(box.style.height) / 100
        const x = leftPct * pw
        const y = ph - (topPct + heightPct) * ph
        const w = widthPct * pw
        const h = heightPct * ph
        page.drawImage(sigImg, { x, y, width: w, height: h })
      }
    }

    const bytes = await pdf.save()
    const blob = new Blob([bytes], { type: "application/pdf" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a"); a.href = url; a.download = "signed.pdf"
    document.body.appendChild(a); a.click(); a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }

  // ----- util -----

  loadSavedSignatures () {
    if (!this.hasSavedSeedTarget || !this.hasSavedListTarget) return

    try {
      this.savedSignatures = JSON.parse(this.savedSeedTarget.textContent || "[]")
    } catch (_) {
      this.savedSignatures = []
    }
    this.renderSavedSignatures()
  }

  renderSavedSignatures () {
    if (!this.hasSavedListTarget) return

    if (this.savedSignatures.length === 0) {
      this.savedListTarget.innerHTML = '<div class="tb-text-sm">No saved signatures yet.</div>'
      return
    }

    this.savedListTarget.innerHTML = this.savedSignatures.map((sig, index) => `
      <button type="button"
              class="tb-tab"
              data-action="click->sign#useSavedSignature"
              data-sign-index-param="${index}"
              style="height: 64px; padding: 6px; background: var(--tb-paper);">
        <img src="${sig.image_data}" alt="${this.escape(sig.name)}" style="max-height: 42px; width: 100%; object-fit: contain;">
      </button>
    `).join("")
  }

  useSavedSignature (event) {
    const sig = this.savedSignatures[event.params.index || 0]
    if (!sig) return

    this.setSignature(sig.image_data, {
      name: sig.name,
      sourceText: sig.source_text || "",
      styleKey: sig.style_key || "saved"
    })
    this.updateDownloadBtn()
  }

  loadImage (src) {
    return new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src })
  }

  cropCanvasToPng (canvas) {
    const { data, width, height } = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height)
    let minX = width, minY = height, maxX = 0, maxY = 0, any = false
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const a = data[(y * width + x) * 4 + 3]
        if (a > 8) {
          any = true
          if (x < minX) minX = x
          if (y < minY) minY = y
          if (x > maxX) maxX = x
          if (y > maxY) maxY = y
        }
      }
    }
    if (!any) return null

    const pad = 8
    const cx = Math.max(0, minX - pad)
    const cy = Math.max(0, minY - pad)
    const cw = Math.min(width, maxX + pad) - cx
    const ch = Math.min(height, maxY + pad) - cy
    const crop = document.createElement("canvas")
    crop.width = cw
    crop.height = ch
    crop.getContext("2d").drawImage(canvas, cx, cy, cw, ch, 0, 0, cw, ch)
    return crop.toDataURL("image/png")
  }

  async pngDataUrlToBytes (url) {
    const res = await fetch(url)
    return new Uint8Array(await res.arrayBuffer())
  }

  toast (msg) {
    const t = document.createElement("div"); t.className = "tb-toast"; t.textContent = msg
    document.body.appendChild(t); setTimeout(() => t.remove(), 2200)
  }

  csrf () {
    const el = document.querySelector('meta[name="csrf-token"]')
    return el ? el.content : ""
  }

  slugify (value) {
    return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40) || "signature"
  }

  escape (value) {
    return String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]))
  }
}

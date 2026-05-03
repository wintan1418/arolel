import { Controller } from "@hotwired/stimulus"
import { PDFDocument, StandardFonts, rgb } from "pdf-lib"

export default class extends Controller {
  static targets = [
    "templates", "sections", "preview", "savedSeed", "savedList",
    "assistantBrief", "aiPrompt", "aiThread", "aiStatus", "fTitle", "fEffective",
    "fPartyAName", "fPartyAAddress", "fPartyAEmail",
    "fPartyBName", "fPartyBAddress", "fPartyBEmail",
    "fSummary", "fNotes",
    "signerPreview", "signerStatus"
  ]

  static values = {
    saved: Boolean,
    slug: String,
    signedIn: Boolean,
    aiEnabled: Boolean,
    seed: Object
  }

  connect () {
    this.savedSignatures = this.loadSavedSignatures()
    this.chatMessages = []
    const seed = this.seedValue || {}
    this.contractData = Object.assign(this.blankContract(seed.template || "service"), seed)

    if (!Array.isArray(this.contractData.sections) || this.contractData.sections.length === 0) {
      this.contractData.sections = this.templateDefaults(this.contractData.template).sections.map((section) => ({ ...section }))
    }

    this.hydrateFields()
    this.renderSections()
    this.renderSavedSignatures()
    this.renderChat()
    this.render()
  }

  blankContract (template) {
    const defaults = this.templateDefaults(template)
    return {
      title: defaults.title,
      template,
      effective_on: this.today(),
      party_a_name: "",
      party_a_address: "",
      party_a_email: "",
      party_b_name: "",
      party_b_address: "",
      party_b_email: "",
      summary: defaults.summary,
      notes: defaults.notes,
      signer_name: "",
      signer_image_data: "",
      sections: defaults.sections.map((section) => ({ ...section }))
    }
  }

  templateDefaults (template) {
    switch (template) {
      case "nda":
        return {
          title: "Mutual NDA",
          summary: "This mutual non-disclosure agreement governs how both parties share, use, and protect confidential information during business discussions.",
          notes: "Review the confidentiality term and governing law before signing.",
          sections: [
            { heading: "Confidential Information", body: "Confidential Information includes non-public business, technical, financial, marketing, client, product, and operational information disclosed by either party in writing, orally, visually, or electronically." },
            { heading: "Use Restrictions", body: "Each party will use the other party's Confidential Information only for evaluating or performing the contemplated business relationship and will not disclose it except to personnel or advisers who need to know and are bound by similar confidentiality duties." },
            { heading: "Exclusions", body: "Confidential Information does not include information that is or becomes public without breach, was already lawfully known, is independently developed without use of the disclosed information, or is lawfully received from a third party without confidentiality restrictions." },
            { heading: "Term", body: "This agreement starts on the Effective Date. Confidentiality obligations survive for the period required by law or, if none applies, for three years after the last disclosure." },
            { heading: "Return of Materials", body: "Upon request, each party will promptly return or destroy the other party's Confidential Information, except for backup copies retained under routine archival systems or legal retention obligations." }
          ]
        }
      case "consulting":
        return {
          title: "Consulting Agreement",
          summary: "This consulting agreement sets the scope, compensation, and working rules for advisory or project-based consulting services.",
          notes: "Confirm payment timing, expense policy, and IP ownership before use.",
          sections: [
            { heading: "Services", body: "Consultant will provide the services described in statements of work, briefs, email approvals, or attached schedules. Work will be carried out with reasonable skill, care, and diligence." },
            { heading: "Compensation", body: "Client will pay Consultant the agreed fees according to the invoicing schedule. Undisputed invoices are due within the agreed payment period after receipt." },
            { heading: "Expenses", body: "Client will reimburse pre-approved out-of-pocket expenses reasonably incurred in connection with the services, provided Consultant supplies supporting documentation." },
            { heading: "Independent Contractor", body: "Consultant performs the services as an independent contractor and not as an employee, agent, or partner of Client. Consultant remains responsible for taxes, insurance, and internal staffing." },
            { heading: "Intellectual Property", body: "Unless otherwise agreed in writing, pre-existing materials remain owned by their original owner. Deliverables created specifically and fully paid for under this agreement transfer or license as stated in the applicable statement of work." },
            { heading: "Termination", body: "Either party may terminate this agreement on written notice if the other party materially breaches and fails to cure within the agreed cure period, or immediately if continued performance would be unlawful." }
          ]
        }
      default:
        return {
          title: "Service Agreement",
          summary: "This service agreement records the work to be delivered, payment expectations, timeline, and ownership terms between the parties.",
          notes: "Review local consumer, employment, and tax rules before signing.",
          sections: [
            { heading: "Scope of Services", body: "Party A will perform the services described in attached briefs, proposals, statements of work, or written approvals exchanged with Party B. Both parties will cooperate in good faith to enable delivery." },
            { heading: "Fees and Payment", body: "Party B will pay the agreed fees according to the approved pricing schedule. Unless a different term is agreed in writing, invoices are due within seven days of issue." },
            { heading: "Timeline and Delivery", body: "Delivery dates depend on timely access, approvals, and feedback from Party B. Reasonable timelines may be adjusted where delays arise outside Party A's control." },
            { heading: "Revisions and Change Requests", body: "Reasonable revisions included in the agreed scope will be handled within the project plan. New requests or material changes may require updated pricing, timing, or both." },
            { heading: "Ownership and License", body: "Each party keeps ownership of materials it owned before this agreement. Final deliverables transfer or license only after full payment, unless the parties agree otherwise in writing." },
            { heading: "Termination", body: "Either party may terminate this agreement on written notice for material breach not cured within a reasonable period. Fees earned and approved expenses incurred up to termination remain payable." }
          ]
        }
    }
  }

  hydrateFields () {
    this.fTitleTarget.value = this.contractData.title || ""
    this.fEffectiveTarget.value = this.contractData.effective_on || this.today()
    this.fPartyANameTarget.value = this.contractData.party_a_name || ""
    this.fPartyAAddressTarget.value = this.contractData.party_a_address || ""
    this.fPartyAEmailTarget.value = this.contractData.party_a_email || ""
    this.fPartyBNameTarget.value = this.contractData.party_b_name || ""
    this.fPartyBAddressTarget.value = this.contractData.party_b_address || ""
    this.fPartyBEmailTarget.value = this.contractData.party_b_email || ""
    this.fSummaryTarget.value = this.contractData.summary || ""
    this.fNotesTarget.value = this.contractData.notes || ""
    this.templatesTarget.querySelectorAll(".tb-tab").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.template === this.contractData.template)
    })
  }

  change () {
    this.contractData.title = this.fTitleTarget.value
    this.contractData.effective_on = this.fEffectiveTarget.value
    this.contractData.party_a_name = this.fPartyANameTarget.value
    this.contractData.party_a_address = this.fPartyAAddressTarget.value
    this.contractData.party_a_email = this.fPartyAEmailTarget.value
    this.contractData.party_b_name = this.fPartyBNameTarget.value
    this.contractData.party_b_address = this.fPartyBAddressTarget.value
    this.contractData.party_b_email = this.fPartyBEmailTarget.value
    this.contractData.summary = this.fSummaryTarget.value
    this.contractData.notes = this.fNotesTarget.value
    this.syncSections()
    this.render()
  }

  setTemplate (e) {
    e.preventDefault()
    const nextTemplate = e.currentTarget.dataset.template
    if (nextTemplate === this.contractData.template) return

    this.syncSections()
    const currentDefaults = this.templateDefaults(this.contractData.template)
    const defaults = this.templateDefaults(nextTemplate)
    const shouldReplaceTitle = !this.contractData.title || this.contractData.title.trim() === currentDefaults.title

    this.contractData.template = nextTemplate
    if (shouldReplaceTitle) this.contractData.title = defaults.title
    this.contractData.summary = defaults.summary
    this.contractData.notes = defaults.notes
    this.contractData.sections = defaults.sections.map((section) => ({ ...section }))
    this.hydrateFields()
    const brief = this.assistantBriefTarget.value.trim()

    if (brief) {
      this.shapeDraftFromBrief(brief)
    } else {
      this.renderSections()
      this.render()
    }

    this.toast(`${e.currentTarget.textContent.trim()} template loaded.`)
  }

  addSection (e) {
    e?.preventDefault()
    this.contractData.sections.push({ heading: "", body: "" })
    this.renderSections()
    this.render()
  }

  removeSection (e) {
    e.preventDefault()
    const idx = parseInt(e.currentTarget.dataset.idx, 10)
    this.contractData.sections.splice(idx, 1)
    if (this.contractData.sections.length === 0) this.addSection()
    this.renderSections()
    this.render()
  }

  syncSections () {
    this.sectionsTarget.querySelectorAll("[data-row]").forEach((row) => {
      const idx = parseInt(row.dataset.row, 10)
      this.contractData.sections[idx] = {
        heading: row.querySelector("[data-f=heading]").value,
        body: row.querySelector("[data-f=body]").value
      }
    })
  }

  renderSections () {
    this.sectionsTarget.innerHTML = this.contractData.sections.map((section, i) => `
      <div class="tb-contract-section-row" data-row="${i}">
        <div class="tb-inline-head">
          <label class="tb-eyebrow">Clause ${i + 1}</label>
          <button type="button" class="tb-btn tb-btn-quiet" data-action="click->contract#removeSection" data-idx="${i}">Remove</button>
        </div>
        <input class="tb-input" data-f="heading" placeholder="Clause heading" value="${this.esc(section.heading || "")}">
        <textarea class="tb-textarea" rows="4" data-f="body" placeholder="Describe the clause clearly.">${this.esc(section.body || "")}</textarea>
      </div>
    `).join("")

    this.sectionsTarget.querySelectorAll("input, textarea").forEach((field) => {
      field.addEventListener("input", () => this.change())
    })
  }

  applyBrief (e) {
    e?.preventDefault()
    const brief = this.promptText()
    if (!brief) {
      this.toast("Add a short deal brief first.")
      return
    }

    this.shapeDraftFromBrief(brief)
    this.toast("Draft reshaped from brief.")
  }

  async askAi (e) {
    e?.preventDefault()
    const prompt = this.promptText()

    if (!prompt) {
      this.toast("Add a contract request first.")
      return
    }

    if (!this.signedInValue) {
      window.location.href = "/login"
      return
    }

    if (!this.aiEnabledValue) {
      this.setAiStatus("OPENAI_API_KEY missing")
      this.toast("Set OPENAI_API_KEY on the server first.")
      return
    }

    this.chatMessages.push({ role: "user", content: prompt })
    this.renderChat()
    this.setAiStatus("Drafting…")
    this.aiPromptTarget.value = ""
    if (this.hasAssistantBriefTarget) this.assistantBriefTarget.value = ""

    const res = await fetch("/contracts/draft", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrf(),
        Accept: "application/json"
      },
      body: JSON.stringify({
        template: this.contractData.template,
        draft: this.currentDraftPayload(),
        messages: this.chatMessages
      })
    })

    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      this.chatMessages.push({ role: "assistant", content: data.message || "The AI draft request failed." })
      this.renderChat()
      this.setAiStatus("Failed")
      this.toast(data.message || "AI draft failed.")
      return
    }

    this.applyAiDraft(data.draft || {})
    this.chatMessages.push({ role: "assistant", content: data.assistant_message || "Draft updated." })
    this.renderChat()
    this.setAiStatus("Ready")
    this.toast("Contract updated from AI draft.")
  }

  applyAiDraft (draft) {
    this.contractData.title = draft.title || this.contractData.title
    this.contractData.summary = draft.summary || ""
    this.contractData.notes = draft.notes || ""
    this.contractData.sections = Array.isArray(draft.sections) && draft.sections.length > 0
      ? draft.sections.map((section) => ({ heading: section.heading || "", body: section.body || "" }))
      : this.contractData.sections
    this.hydrateFields()
    this.renderSections()
    this.render()
  }

  renderChat () {
    if (!this.hasAiThreadTarget) return

    if (this.chatMessages.length === 0) {
      this.aiThreadTarget.innerHTML = `
        <div class="tb-contract-chat-empty">
          Ask for a redraft, new clauses, payment terms, confidentiality language, or a different tone.
        </div>
      `
      return
    }

    this.aiThreadTarget.innerHTML = this.chatMessages.map((message) => `
      <div class="tb-contract-chat-bubble is-${message.role}">
        <div class="tb-eyebrow">${message.role === "user" ? "You" : "Assistant"}</div>
        <p>${this.esc(message.content)}</p>
      </div>
    `).join("")
    this.aiThreadTarget.scrollTop = this.aiThreadTarget.scrollHeight
  }

  setAiStatus(message) {
    if (this.hasAiStatusTarget) this.aiStatusTarget.textContent = message
  }

  promptText () {
    const primary = this.hasAiPromptTarget ? this.aiPromptTarget.value.trim() : ""
    if (primary) return primary
    return this.hasAssistantBriefTarget ? this.assistantBriefTarget.value.trim() : ""
  }

  currentDraftPayload () {
    return {
      title: this.contractData.title || "",
      effective_on: this.contractData.effective_on || "",
      party_a_name: this.contractData.party_a_name || "",
      party_a_address: this.contractData.party_a_address || "",
      party_a_email: this.contractData.party_a_email || "",
      party_b_name: this.contractData.party_b_name || "",
      party_b_address: this.contractData.party_b_address || "",
      party_b_email: this.contractData.party_b_email || "",
      summary: this.contractData.summary || "",
      notes: this.contractData.notes || "",
      sections: this.contractData.sections.map((section) => ({
        heading: section.heading || "",
        body: section.body || ""
      }))
    }
  }

  shapeDraftFromBrief (brief) {
    const defaults = this.templateDefaults(this.contractData.template)
    const sections = defaults.sections.map((section) => ({ ...section }))
    const lower = brief.toLowerCase()

    this.contractData.summary = `${defaults.summary} Deal brief: ${brief}`

    if (lower.includes("payment") || lower.includes("retainer") || lower.includes("milestone")) {
      this.upsertSection(sections, "Fees and Payment", "Fees, deposit requirements, milestone payments, late fees, and invoicing expectations will follow the commercial terms described by the parties. " + brief)
      this.upsertSection(sections, "Compensation", "Compensation, retainers, milestone billing, and payment timing will follow the written commercial terms agreed by the parties. " + brief)
    }

    if (lower.includes("confidential")) {
      this.upsertSection(sections, "Confidentiality", "Both parties will protect confidential information shared under this relationship and use it only for performing or evaluating the contract. " + brief)
    }

    if (lower.includes("revision") || lower.includes("feedback")) {
      this.upsertSection(sections, "Revisions and Change Requests", "Included revisions, review windows, and any chargeable scope changes will follow the parties' written approvals and feedback cadence. " + brief)
    }

    if (lower.includes("deadline") || lower.includes("timeline")) {
      this.upsertSection(sections, "Timeline and Delivery", "Project timing, deadlines, and acceptance windows will be managed according to the delivery expectations described by the parties. " + brief)
    }

    if (lower.includes("ip") || lower.includes("intellectual property") || lower.includes("ownership")) {
      this.upsertSection(sections, "Ownership and License", "Ownership, license scope, transfer timing, and any retained rights will follow the parties' written understanding reflected in this brief. " + brief)
      this.upsertSection(sections, "Intellectual Property", "Ownership, assignment, and license rights for deliverables and pre-existing materials will follow the parties' written understanding reflected in this brief. " + brief)
    }

    if (lower.includes("termination") || lower.includes("cancel")) {
      this.upsertSection(sections, "Termination", "Termination notice periods, cure rights, and post-termination obligations will follow the commercial arrangement described by the parties. " + brief)
    }

    if (lower.includes("exclusive")) {
      this.upsertSection(sections, "Exclusivity", "Where the parties intend an exclusive relationship, the scope, duration, and carve-outs for that exclusivity will be interpreted consistently with this brief. " + brief)
    }

    this.contractData.sections = sections
    this.renderSections()
    this.hydrateFields()
    this.render()
  }

  upsertSection (sections, heading, body) {
    const existing = sections.find((section) => section.heading.toLowerCase() === heading.toLowerCase())
    if (existing) {
      existing.body = body
    } else {
      sections.push({ heading, body })
    }
  }

  loadSavedSignatures () {
    if (!this.hasSavedSeedTarget) return []

    try {
      return JSON.parse(this.savedSeedTarget.textContent || "[]")
    } catch (_) {
      return []
    }
  }

  renderSavedSignatures () {
    if (!this.hasSavedListTarget) return

    if (this.savedSignatures.length === 0) {
      this.savedListTarget.innerHTML = '<div class="tb-text-sm">No saved signatures yet. Create one in the Sign tool first.</div>'
      return
    }

    this.savedListTarget.innerHTML = this.savedSignatures.map((signature, idx) => `
      <div class="tb-contract-saved-card">
        <div class="tb-contract-saved-preview"><img src="${signature.image_data}" alt="${this.esc(signature.name || "Saved signature")}"></div>
        <div class="tb-contract-saved-foot">
          <div class="tb-dash-name">${this.esc(signature.name || `Signature ${idx + 1}`)}</div>
          <button type="button" class="tb-btn tb-btn-ghost tb-btn-sm" data-saved-idx="${idx}">Use on contract</button>
        </div>
      </div>
    `).join("")

    this.savedListTarget.querySelectorAll("[data-saved-idx]").forEach((button) => {
      button.addEventListener("click", () => this.useSavedSignature(parseInt(button.dataset.savedIdx, 10)))
    })
  }

  useSavedSignature (idx) {
    const signature = this.savedSignatures[idx]
    if (!signature) return

    this.contractData.signer_name = signature.name || signature.source_text || "Signature"
    this.contractData.signer_image_data = signature.image_data
    this.render()
    this.toast("Saved signature added to the contract.")
  }

  clearSignature (e) {
    e?.preventDefault()
    this.contractData.signer_name = ""
    this.contractData.signer_image_data = ""
    this.render()
  }

  render () {
    this.renderSigner()
    this.previewTarget.innerHTML = this.previewHtml()
  }

  renderSigner () {
    if (!this.contractData.signer_image_data) {
      this.signerPreviewTarget.innerHTML = `
        <div class="tb-text-sm tb-muted">
          No signature selected. Pick one from your saved signatures to stamp the creator line in the PDF.
        </div>
      `
      this.signerStatusTarget.textContent = "No saved signature selected."
      return
    }

    this.signerStatusTarget.textContent = `${this.contractData.signer_name || "Saved signature"} selected`
    this.signerPreviewTarget.innerHTML = `
      <div class="tb-contract-signature-card">
        <img src="${this.contractData.signer_image_data}" alt="${this.esc(this.contractData.signer_name || "Saved signature")}">
        <div class="tb-actions-inline" style="margin-top: 10px;">
          <strong>${this.esc(this.contractData.signer_name || "Saved signature")}</strong>
          <button type="button" class="tb-btn tb-btn-quiet tb-btn-sm" data-clear-signature="1">Clear</button>
        </div>
      </div>
    `

    const button = this.signerPreviewTarget.querySelector("[data-clear-signature]")
    button?.addEventListener("click", (event) => this.clearSignature(event))
  }

  previewHtml () {
    const sections = this.contractData.sections.map((section) => `
      <section style="margin-top: 14px;">
        <div class="tb-eyebrow">${this.esc(section.heading || "Clause")}</div>
        <p style="margin-top: 6px; white-space: pre-line; color: var(--tb-ink-2); line-height: 1.7;">${this.esc(section.body || "")}</p>
      </section>
    `).join("")

    const signer = this.contractData.signer_image_data
      ? `<div style="margin-top: 10px;"><img src="${this.contractData.signer_image_data}" alt="${this.esc(this.contractData.signer_name || "Signature")}" style="max-height: 56px; max-width: 180px;"></div><div class="tb-mono" style="margin-top: 8px;">${this.esc(this.contractData.signer_name || "")}</div>`
      : `<div class="tb-mono" style="margin-top: 28px; border-top: 1px solid var(--tb-line); padding-top: 10px;">Party A signature</div>`

    return `
      <div style="display:flex; justify-content:space-between; gap:12px; align-items:flex-start;">
        <div>
          <div class="tb-eyebrow">${this.esc(this.contractData.template.toUpperCase())}</div>
          <h2 style="font-family: var(--font-serif); font-size: 24px; margin-top: 8px; line-height: 1.08;">${this.esc(this.contractData.title || "Contract")}</h2>
        </div>
        <div class="tb-mono" style="font-size: 11px; color: var(--tb-muted); text-align: right;">Effective ${this.esc(this.contractData.effective_on || this.today())}</div>
      </div>

      <div class="tb-field-grid-2" style="margin-top: 16px;">
        <div>
          <div class="tb-eyebrow">Party A</div>
          <div style="font-weight: 600; margin-top: 5px;">${this.esc(this.contractData.party_a_name || "—")}</div>
          <div style="white-space: pre-line; color: var(--tb-muted);">${this.esc(this.contractData.party_a_address || "")}</div>
          <div class="tb-mono" style="font-size: 11px; color: var(--tb-muted);">${this.esc(this.contractData.party_a_email || "")}</div>
        </div>
        <div>
          <div class="tb-eyebrow">Party B</div>
          <div style="font-weight: 600; margin-top: 5px;">${this.esc(this.contractData.party_b_name || "—")}</div>
          <div style="white-space: pre-line; color: var(--tb-muted);">${this.esc(this.contractData.party_b_address || "")}</div>
          <div class="tb-mono" style="font-size: 11px; color: var(--tb-muted);">${this.esc(this.contractData.party_b_email || "")}</div>
        </div>
      </div>

      <section style="margin-top: 16px;">
        <div class="tb-eyebrow">Purpose</div>
        <p style="margin-top: 6px; white-space: pre-line; color: var(--tb-ink-2); line-height: 1.7;">${this.esc(this.contractData.summary || "")}</p>
      </section>

      ${sections}

      ${this.contractData.notes ? `<section style="margin-top: 16px;"><div class="tb-eyebrow">Notes</div><p style="margin-top: 6px; white-space: pre-line; color: var(--tb-muted); line-height: 1.7;">${this.esc(this.contractData.notes)}</p></section>` : ""}

      <div class="tb-field-grid-2" style="margin-top: 22px;">
        <div>${signer}</div>
        <div>
          <div class="tb-mono" style="margin-top: 84px; border-top: 1px solid var(--tb-line); padding-top: 10px;">Party B signature</div>
        </div>
      </div>
    `
  }

  async download (e) {
    e?.preventDefault()
    const pdf = await PDFDocument.create()
    const fonts = await this.fonts(pdf)
    const state = this.newState(pdf)
    const palette = this.paletteFor(this.contractData.template)

    this.drawHeader(state, fonts, palette)
    this.drawPartyGrid(state, fonts, palette)
    this.drawSection(state, fonts, "Purpose", this.contractData.summary, palette)
    this.contractData.sections.forEach((section) => {
      this.drawSection(state, fonts, section.heading || "Clause", section.body || "", palette)
    })
    if (this.contractData.notes) {
      this.drawSection(state, fonts, "Notes", this.contractData.notes, palette)
    }
    await this.drawSignatureBlock(state, fonts, palette)

    const bytes = await pdf.save()
    const blob = new Blob([bytes], { type: "application/pdf" })
    const fileName = `${(this.contractData.title || "contract").replace(/\s+/g, "-").toLowerCase()}.pdf`
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = fileName
    document.body.appendChild(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }

  paletteFor (template) {
    switch (template) {
      case "nda":
        return { label: "Mutual NDA", accent: rgb(0.24, 0.24, 0.52), fill: rgb(0.94, 0.94, 0.99) }
      case "consulting":
        return { label: "Consulting Agreement", accent: rgb(0.16, 0.43, 0.34), fill: rgb(0.92, 0.98, 0.95) }
      default:
        return { label: "Service Agreement", accent: rgb(0.49, 0.16, 0.18), fill: rgb(0.99, 0.95, 0.95) }
    }
  }

  newState (pdf) {
    return { pdf, page: pdf.addPage([595, 842]), x: 48, right: 547, y: 792, bottom: 56 }
  }

  addPage (state) {
    state.page = state.pdf.addPage([595, 842])
    state.y = 792
  }

  ensureSpace (state, required = 20) {
    if (state.y - required < state.bottom) this.addPage(state)
  }

  async fonts (pdf) {
    return {
      regular: await pdf.embedFont(StandardFonts.Helvetica),
      bold: await pdf.embedFont(StandardFonts.HelveticaBold),
      mono: await pdf.embedFont(StandardFonts.Courier)
    }
  }

  drawHeader (state, fonts, palette) {
    const { page, x, right } = state
    page.drawRectangle({ x, y: state.y - 40, width: right - x, height: 54, color: palette.fill })
    page.drawText(palette.label, { x: x + 14, y: state.y - 18, size: 23, font: fonts.bold, color: palette.accent })
    this.drawRight(page, this.contractData.effective_on || this.today(), { x: right - 14, y: state.y - 18, size: 10, font: fonts.mono, color: palette.accent })
    this.drawRight(page, this.contractData.title || "Contract", { x: right - 14, y: state.y - 34, size: 10, font: fonts.regular, color: rgb(0.35, 0.35, 0.35) })
    state.y -= 72
  }

  drawPartyGrid (state, fonts, palette) {
    this.ensureSpace(state, 110)
    const leftX = state.x
    const rightX = state.x + 255
    this.drawPartyBlock(state.page, fonts, leftX, state.y, "Party A", [
      this.contractData.party_a_name,
      this.contractData.party_a_address,
      this.contractData.party_a_email
    ], palette)
    this.drawPartyBlock(state.page, fonts, rightX, state.y, "Party B", [
      this.contractData.party_b_name,
      this.contractData.party_b_address,
      this.contractData.party_b_email
    ], palette)
    state.y -= 98
  }

  drawPartyBlock (page, fonts, x, y, label, lines, palette) {
    page.drawText(label.toUpperCase(), { x, y, size: 8, font: fonts.mono, color: palette.accent })
    let cursor = y - 16
    this.wrapText((lines[0] || "—").toString(), fonts.bold, 11, 210).forEach((line) => {
      page.drawText(line, { x, y: cursor, size: 11, font: fonts.bold, color: rgb(0.1, 0.1, 0.1) })
      cursor -= 14
    })
    this.wrapText((lines[1] || "").toString(), fonts.regular, 10, 210).forEach((line) => {
      page.drawText(line, { x, y: cursor, size: 10, font: fonts.regular, color: rgb(0.38, 0.38, 0.38) })
      cursor -= 13
    })
    this.wrapText((lines[2] || "").toString(), fonts.mono, 9, 210).forEach((line) => {
      page.drawText(line, { x, y: cursor, size: 9, font: fonts.mono, color: rgb(0.45, 0.45, 0.45) })
      cursor -= 12
    })
  }

  drawSection (state, fonts, heading, body, palette) {
    const sectionHeading = (heading || "Clause").toString()
    const sectionBody = (body || "").toString()
    this.ensureSpace(state, 38)
    state.page.drawText(sectionHeading, { x: state.x, y: state.y, size: 12, font: fonts.bold, color: palette.accent })
    state.y -= 18
    this.drawParagraph(state, fonts.regular, 10.5, sectionBody, 499, 14, rgb(0.16, 0.16, 0.16))
    state.y -= 10
  }

  drawParagraph (state, font, size, text, width, leading, color) {
    const lines = this.wrapText((text || "—").toString(), font, size, width)
    lines.forEach((line) => {
      this.ensureSpace(state, leading + 4)
      state.page.drawText(line, { x: state.x, y: state.y, size, font, color })
      state.y -= leading
    })
  }

  async drawSignatureBlock (state, fonts, palette) {
    this.ensureSpace(state, 140)
    const leftX = state.x
    const rightX = state.x + 285
    const lineY = state.y - 58

    if (this.contractData.signer_image_data) {
      const image = await state.pdf.embedPng(this.pngBytes(this.contractData.signer_image_data))
      const dims = image.scaleToFit(150, 54)
      state.page.drawImage(image, { x: leftX, y: lineY + 14, width: dims.width, height: dims.height })
    }

    state.page.drawLine({ start: { x: leftX, y: lineY }, end: { x: leftX + 200, y: lineY }, thickness: 0.8, color: palette.accent })
    state.page.drawLine({ start: { x: rightX, y: lineY }, end: { x: rightX + 200, y: lineY }, thickness: 0.8, color: palette.accent })
    state.page.drawText(this.contractData.signer_name || "Party A signature", { x: leftX, y: lineY - 14, size: 9, font: fonts.mono, color: rgb(0.4, 0.4, 0.4) })
    state.page.drawText("Party B signature", { x: rightX, y: lineY - 14, size: 9, font: fonts.mono, color: rgb(0.4, 0.4, 0.4) })
    state.y = lineY - 34
  }

  wrapText (text, font, size, maxWidth) {
    if (!text) return [""]
    const words = text.replace(/\r/g, "").split(/\s+/)
    const lines = []
    let current = ""

    words.forEach((word) => {
      const candidate = current ? `${current} ${word}` : word
      if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
        current = candidate
      } else if (current) {
        lines.push(current)
        current = word
      } else {
        lines.push(word)
        current = ""
      }
    })

    if (current) lines.push(current)

    return lines.flatMap((line) => line.split("\n"))
  }

  drawRight (page, text, opts) {
    const width = opts.font.widthOfTextAtSize(text, opts.size)
    page.drawText(text, { ...opts, x: opts.x - width })
  }

  pngBytes (dataUrl) {
    const base64 = dataUrl.split(",")[1] || ""
    return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0))
  }

  async save (e) {
    e?.preventDefault()
    if (!this.signedInValue) {
      window.location.href = "/login"
      return
    }

    const body = new FormData()
    body.append("contract[title]", this.contractData.title || "")
    body.append("contract[template]", this.contractData.template || "service")
    body.append("contract[effective_on]", this.contractData.effective_on || "")
    body.append("contract[party_a_name]", this.contractData.party_a_name || "")
    body.append("contract[party_a_address]", this.contractData.party_a_address || "")
    body.append("contract[party_a_email]", this.contractData.party_a_email || "")
    body.append("contract[party_b_name]", this.contractData.party_b_name || "")
    body.append("contract[party_b_address]", this.contractData.party_b_address || "")
    body.append("contract[party_b_email]", this.contractData.party_b_email || "")
    body.append("contract[summary]", this.contractData.summary || "")
    body.append("contract[notes]", this.contractData.notes || "")
    body.append("contract[signer_name]", this.contractData.signer_name || "")
    body.append("contract[signer_image_data]", this.contractData.signer_image_data || "")
    this.contractData.sections.forEach((section) => {
      body.append("contract[sections][][heading]", section.heading || "")
      body.append("contract[sections][][body]", section.body || "")
    })

    const url = this.savedValue ? `/contracts/${this.slugValue}` : "/contracts"
    const method = this.savedValue ? "PATCH" : "POST"
    const res = await fetch(url, {
      method,
      headers: { "X-CSRF-Token": this.csrf(), Accept: "application/json" },
      body
    })

    if (res.ok) {
      window.location.href = "/dashboard"
    } else {
      const msg = await res.text()
      this.toast("Couldn't save: " + msg.slice(0, 120))
    }
  }

  today () {
    return new Date().toISOString().slice(0, 10)
  }

  csrf () {
    const el = document.querySelector('meta[name="csrf-token"]')
    return el ? el.content : ""
  }

  esc (value) {
    return String(value || "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]))
  }

  toast (msg) {
    const toast = document.createElement("div")
    toast.className = "tb-toast"
    toast.textContent = msg
    document.body.appendChild(toast)
    setTimeout(() => toast.remove(), 2800)
  }
}

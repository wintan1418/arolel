// Per-tab draft persistence for the form-based tools (invoice, contract).
//
// Drafts live in sessionStorage so that hopping to another Arolel tool (for
// example the Sign tool to create a signature) and coming back restores the
// in-progress work. The tab closing clears everything, which keeps private
// data from lingering on shared machines.

const PREFIX = "arolel:draft:"

function storage () {
  try {
    return window.sessionStorage
  } catch (_) {
    return null
  }
}

export function loadDraft (key) {
  const store = storage()
  if (!store) return null
  try {
    const raw = store.getItem(PREFIX + key)
    if (!raw) return null
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === "object" ? parsed : null
  } catch (_) {
    return null
  }
}

export function saveDraft (key, data) {
  const store = storage()
  if (!store) return false
  try {
    store.setItem(PREFIX + key, JSON.stringify({ ...data, saved_at: Date.now() }))
    return true
  } catch (_) {
    // Quota exceeded (large signature image) or storage disabled — fail quietly.
    return false
  }
}

export function clearDraft (key) {
  const store = storage()
  if (!store) return
  try {
    store.removeItem(PREFIX + key)
  } catch (_) {}
}

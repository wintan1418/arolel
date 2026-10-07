// Warns before leaving a tool page that still holds in-progress work.
//
// The file tools (HEIC, images, PDF, sign) keep everything in memory on
// purpose — nothing is uploaded — so a Turbo visit to another tool would
// silently throw that work away. Each tool registers a predicate that says
// whether it currently has unsaved work; this module asks every predicate
// before a Turbo visit or a full unload and lets the user cancel.
//
// The registry hangs off `window` because each tool ships in its own esbuild
// bundle, so module-level state would not be shared.

const MESSAGE = "You have files in progress on this page. Leaving now will discard them. Leave anyway?"

function registry () {
  if (!window.__arolelUnsavedWork) window.__arolelUnsavedWork = new Set()
  return window.__arolelUnsavedWork
}

export function hasUnsavedWork () {
  for (const check of registry()) {
    try {
      if (check()) return true
    } catch (_) {}
  }
  return false
}

// Returns an unregister function. Call it from the controller's disconnect().
export function guardUnsavedWork (check) {
  registry().add(check)
  return () => registry().delete(check)
}

export function installUnsavedWorkGuard () {
  if (window.__arolelUnsavedWorkInstalled) return
  window.__arolelUnsavedWorkInstalled = true

  document.addEventListener("turbo:before-visit", (event) => {
    if (!hasUnsavedWork()) return
    if (!window.confirm(MESSAGE)) event.preventDefault()
  })

  window.addEventListener("beforeunload", (event) => {
    if (!hasUnsavedWork()) return
    event.preventDefault()
    // Legacy browsers need returnValue set to show the prompt.
    event.returnValue = ""
  })

  // Turbo drops the old page's controllers on a successful visit, so a
  // stale predicate can never survive navigation. Clear defensively anyway.
  document.addEventListener("turbo:load", () => {
    const set = registry()
    for (const check of Array.from(set)) {
      if (check.__arolelDetached) set.delete(check)
    }
  })
}

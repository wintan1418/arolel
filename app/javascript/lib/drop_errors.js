// Inline rejection messages for the drop zones. Every file a tool refuses
// gets a sentence naming the file and what the tool accepts, instead of
// disappearing silently.
export function describeRejected (files, accepted, hint) {
  if (!files.length) return ""
  const names = files.slice(0, 3).map((f) => f.name).join(", ")
  const more = files.length > 3 ? ` and ${files.length - 3} more` : ""
  const plural = files.length > 1
  return `${names}${more} ${plural ? "aren't" : "isn't"} ${accepted}.${hint ? " " + hint : ""}`
}

export function showDropError (el, message) {
  if (!el) return
  if (!message) {
    el.hidden = true
    el.textContent = ""
    return
  }
  el.textContent = message
  el.hidden = false
}

// One toast region for the whole page: announced to screen readers, stacks
// instead of overlapping, full width on phones, and errors stay long enough
// to read.
export function showToast (message, { type = "info", duration } = {}) {
  let region = document.querySelector(".tb-toasts")
  if (!region) {
    region = document.createElement("div")
    region.className = "tb-toasts"
    region.setAttribute("role", "status")
    region.setAttribute("aria-live", "polite")
    document.body.appendChild(region)
  }
  const el = document.createElement("div")
  el.className = "tb-toast" + (type === "error" ? " is-error" : "")
  el.textContent = message
  region.appendChild(el)
  const ttl = duration || (type === "error" ? 6500 : 3000)
  setTimeout(() => {
    el.remove()
    if (!region.childElementCount) region.remove()
  }, ttl)
  return el
}

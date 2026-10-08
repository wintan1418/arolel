// One toast region for the whole page: announced to screen readers, stacks
// instead of overlapping, full width on phones, and errors stay long enough
// to read.
export function showToast (message, { type = "info", duration, href, linkText } = {}) {
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
  if (href) {
    const link = document.createElement("a")
    link.href = href
    link.textContent = linkText || "Open"
    el.appendChild(link)
  }
  region.appendChild(el)
  const ttl = duration || (type === "error" || href ? 6500 : 3000)
  setTimeout(() => {
    el.remove()
    if (!region.childElementCount) region.remove()
  }, ttl)
  return el
}

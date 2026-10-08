// Toggle-tab helper: keeps the visual state and aria-pressed in sync so
// assistive tech can tell which option is selected.
export function pressTab (group, active) {
  if (!group) return
  group.querySelectorAll(".tb-tab").forEach((button) => {
    const on = button === active
    button.classList.toggle("is-active", on)
    button.setAttribute("aria-pressed", String(on))
  })
}

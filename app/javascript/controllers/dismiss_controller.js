import { Controller } from "@hotwired/stimulus"

// Removes its element (used by flash messages and inline notices).
export default class extends Controller {
  remove () {
    this.element.remove()
  }
}

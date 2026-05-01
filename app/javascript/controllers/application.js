import { Application } from "@hotwired/stimulus"

const application = window.Stimulus || Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }

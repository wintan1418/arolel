// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import { installUnsavedWorkGuard } from "./lib/unsaved_work"

installUnsavedWorkGuard()

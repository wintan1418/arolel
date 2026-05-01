import { application } from "./controllers/application"
import DropzoneController from "./controllers/dropzone_controller"
import HeicController from "./controllers/heic_controller"

application.register("dropzone", DropzoneController)
application.register("heic", HeicController)

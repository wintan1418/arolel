import { application } from "./controllers/application"
import DropzoneController from "./controllers/dropzone_controller"
import MediaController from "./controllers/media_controller"

application.register("dropzone", DropzoneController)
application.register("media", MediaController)

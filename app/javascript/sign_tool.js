import { application } from "./controllers/application"
import DropzoneController from "./controllers/dropzone_controller"
import SignController from "./controllers/sign_controller"

application.register("dropzone", DropzoneController)
application.register("sign", SignController)

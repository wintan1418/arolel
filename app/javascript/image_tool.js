import { application } from "./controllers/application"
import DropzoneController from "./controllers/dropzone_controller"
import ImageCompressController from "./controllers/image_compress_controller"

application.register("dropzone", DropzoneController)
application.register("image-compress", ImageCompressController)

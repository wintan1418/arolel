import { application } from "./controllers/application"
import DropzoneController from "./controllers/dropzone_controller"
import PdfController from "./controllers/pdf_controller"

application.register("dropzone", DropzoneController)
application.register("pdf", PdfController)

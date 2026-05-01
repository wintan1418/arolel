import { application } from "./controllers/application"
import DocumentConversionController from "./controllers/document_conversion_controller"

application.register("document-conversion", DocumentConversionController)

import { application } from "./controllers/application"
import InvoiceController from "./controllers/invoice_controller"

application.register("invoice", InvoiceController)

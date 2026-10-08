import { application } from "./controllers/application"
import DropzoneController from "./controllers/dropzone_controller"
import MediaController from "./controllers/media_controller"
import JobStatusController from "./controllers/job_status_controller"

application.register("dropzone", DropzoneController)
application.register("media", MediaController)
application.register("job-status", JobStatusController)

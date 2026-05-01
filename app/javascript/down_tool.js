import { application } from "./controllers/application"
import DownController from "./controllers/down_controller"

application.register("down", DownController)

import { application } from "./controllers/application"
import UrlOpenerController from "./controllers/url_opener_controller"

application.register("url-opener", UrlOpenerController)

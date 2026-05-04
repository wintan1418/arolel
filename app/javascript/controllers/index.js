import { application } from "./application"

import MobileNavController from "./mobile_nav_controller"
import ReceiptController from "./receipt_controller"
import SignupNudgeController from "./signup_nudge_controller"

application.register("mobile-nav", MobileNavController)
application.register("receipt", ReceiptController)
application.register("signup-nudge", SignupNudgeController)

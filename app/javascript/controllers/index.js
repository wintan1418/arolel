import { application } from "./application"

import ReceiptController from "./receipt_controller"
import SignupNudgeController from "./signup_nudge_controller"

application.register("receipt", ReceiptController)
application.register("signup-nudge", SignupNudgeController)

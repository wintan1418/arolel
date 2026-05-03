import { application } from "./controllers/application"
import ContractController from "./controllers/contract_controller"

application.register("contract", ContractController)

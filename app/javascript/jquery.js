import $ from "jquery"

// coloca no window **antes**
window.$ = $
window.jQuery = $

// só depois importa o blockUI
require("jquery-blockui")
import { blockPage, unblockPage } from "./helpers/loading"

window.blockPage = blockPage
window.unblockPage = unblockPage
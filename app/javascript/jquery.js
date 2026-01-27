import $ from "jquery"

// coloca no window **antes**
window.$ = $
window.jQuery = $

// só depois importa o blockUI
require("jquery-blockui")
import { blockPage, unblockPage, blockProgress } from "./helpers/loading"

window.blockPage = blockPage
window.unblockPage = unblockPage
window.blockProgress = blockProgress

import 'select2';                       

import select2 from 'select2';
select2($);

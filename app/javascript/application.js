// 1) jQuery base (mantém global p/ plugins antigos)
import "./jquery"

// 2) Turbo e Stimulus
import "@hotwired/turbo-rails"
import "./controllers"

// 3) Dependências que o Color Admin costuma usar (mínimo viável)
import "./pace_bridge"
import "pace-js"
import Cookies from "js-cookie"

// jQuery UI: escolha UM caminho
import "./jquery-ui"

// 4) Bootstrap (tu já tem no package.json)
import * as bootstrap from "bootstrap"
window.bootstrap = bootstrap // se o app do template esperar global

// 5) Color Admin "app" (SEM o vendorzão)
import "../../vendor/assets/color-admin/js/app"

// 6) Bridge Turbo para Color Admin (seu arquivo)
import "./color_admin_turbo_bridge"

// 7) Client-side validations
import '@client-side-validations/client-side-validations/src'
import './guards/devise_instant_nav.js'
import "./csv_bootstrap_floating"

import "./datatable.js"
import "./turbo_listener.js"
import 'parsleyjs'

// app/javascript/controllers/datatable_controller.js
import { Controller } from "@hotwired/stimulus"
import DataTable from "datatables.net-bs5"
import "datatables.net-responsive-bs5" // mantém o responsive funcional

export default class extends Controller {
  connect() {
    // já inicializado? então não faz nada
    if (this.element.dataset.dtInitialized === "true") {
      this.table = this.element._dt
      return
    }

    // inicializa uma única vez
    this.table = new DataTable(this.element, {
      responsive: true,
      paging: true,
      searching: true,
      info: true,
      autoWidth: false
    })

    // marca e guarda a instância no elemento
    this.element.dataset.dtInitialized = "true"
    this.element._dt = this.table
  }

  // Nada no disconnect() para evitar loop com Turbo
  // Se um dia precisar destruir quando o nó sumir de verdade, use:
  // disconnect() {
  //   queueMicrotask(() => {
  //     if (!document.body.contains(this.element) && this.element._dt) {
  //       this.element._dt.destroy()
  //       delete this.element._dt
  //       delete this.element.dataset.dtInitialized
  //     }
  //   })
  // }
}

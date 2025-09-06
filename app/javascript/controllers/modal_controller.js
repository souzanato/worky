// app/javascript/controllers/modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // auto-show quando o conteúdo conecta
    this.modal = new bootstrap.Modal(this.element)
    this.modal.show()

    // limpar frame ao fechar
    this.element.addEventListener("hidden.bs.modal", () => {
      const frame = this.element.closest("turbo-frame#modal")
      if (frame) frame.innerHTML = ""    // fecha de verdade removendo o conteúdo
    })
  }

  closeIfSuccessful(event) {
    // dispara em <form data-action="turbo:submit-end->modal#closeIfSuccessful">
    if (event.detail.success) {
      this.modal.hide()
    }
  }

  hide() { this.modal?.hide() }
}

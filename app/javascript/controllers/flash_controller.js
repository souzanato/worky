import { Controller } from "@hotwired/stimulus"

// Mostra toasts do Bootstrap para cada mensagem presente no DOM.
// Usa data-flash-target="toast" nos elementos .toast.
export default class extends Controller {
  static targets = ["toast"]

  connect() {
    this._instances = []
    this.showAll()
  }

  disconnect() {
    // limpa instâncias ao sair da página / turbo cache
    this._instances?.forEach(i => i.hide?.())
    this._instances = []
  }

  showAll() {
    // Garante que o Bootstrap está disponível globalmente (você já fez window.bootstrap = bootstrap)
    if (!window.bootstrap) return
    this.toastTargets.forEach((el) => {
      // se vier sem delay no HTML, aplica um default
      if (!el.hasAttribute("data-bs-delay")) el.setAttribute("data-bs-delay", "5000")
      const inst = new bootstrap.Toast(el)
      this._instances.push(inst)
      inst.show()
    })
  }
}
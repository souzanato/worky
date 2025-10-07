// app/javascript/controllers/ai_record_launcher_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  open(event) {
    event.preventDefault()

    let modalEl = document.getElementById("aiRecordModal")

    if (!modalEl) {
      // Carrega o conteúdo via Turbo Stream
      fetch("/ai_records/new", { headers: { Accept: "text/vnd.turbo-stream.html" } })
        .then(response => response.text())
        .then(html => {
          // Cria um template temporário pra processar o Turbo Stream
          const template = document.createElement("template")
          template.innerHTML = html.trim()

          // Insere o conteúdo do <turbo-stream> no body
          template.content.querySelectorAll("turbo-stream").forEach(streamEl => {
            document.body.insertAdjacentHTML("beforeend", streamEl.querySelector("template").innerHTML)
          })

          // Depois de inserir, pega a modal
          modalEl = document.getElementById("aiRecordModal")
          this.showModal(modalEl)
        })
        .catch(error => {
          console.error("Error loading AiRecord modal:", error)
          alert("Error loading AI Record modal. Please try again.")
        })
    } else {
      this.showModal(modalEl)
    }
  }

  showModal(modalEl) {
    if (modalEl) {
      const modal = new bootstrap.Modal(modalEl)
      modal.show()

      // Força a primeira aba (Transcription)
      const firstTab = modalEl.querySelector('[href="#tab-transcription"]')
      if (firstTab) {
        const tab = new bootstrap.Tab(firstTab)
        tab.show()
      }
    } else {
      console.warn("Modal #aiRecordModal not found even after fetch")
    }
  }
}

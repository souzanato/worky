// app/javascript/controllers/step_action_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "hasAiActionCheckbox",
    "aiModelSelect",
    "aiModelLabel",
    "hasBestModalPickerCheckbox"
  ]

  connect() {
    // listeners
    this.hasAiActionCheckboxTarget.addEventListener("change", () => {
      this.applyState()
    })

    this.hasBestModalPickerCheckboxTarget.addEventListener("change", () => {
      this.applyState()
    })

    // estado inicial (antes do Select2)
    this.applyState()

    // 🔑 garante estado correto após init do Select2
    requestAnimationFrame(() => {
      this.applyState()
    })

    setTimeout(() => {
      this.applyState()
    }, 0)
  }

  /* =====================================================
     FONTE ÚNICA DA VERDADE
  ====================================================== */
  applyState() {
    const aiEnabled = this.hasAiActionCheckboxTarget.checked
    const bestPickerEnabled = this.hasBestModalPickerCheckboxTarget.checked

    /* -------------------------
       Best Model Picker
    -------------------------- */
    this.hasBestModalPickerCheckboxTarget.disabled = !aiEnabled

    /* -------------------------
       AI Model Select
    -------------------------- */
    const disableAiModel = !aiEnabled || bestPickerEnabled
    this.setAiModelDisabled(disableAiModel)
  }

  /* =====================================================
     HELPERS
  ====================================================== */

  setAiModelDisabled(disabled) {
    const select = this.aiModelSelectTarget

    // select nativo
    select.disabled = disabled
    this.aiModelLabelTarget.classList.toggle("text-muted", disabled)

    // Select2
    if (window.$ && $(select).data("select2")) {
      $(select)
        .prop("disabled", disabled)
        .trigger("change.select2")

      this.applySelect2DisabledStyles(disabled)
    }
  }

  // 🎨 visual muted via JS (sem CSS global)
  applySelect2DisabledStyles(disabled) {
    const select = this.aiModelSelectTarget
    if (!window.$ || !$(select).data("select2")) return

    const container = $(select).data("select2").$container
    const selection = container.find(".select2-selection")
    const rendered = container.find(".select2-selection__rendered")
    const arrow = container.find(".select2-selection__arrow")

    if (disabled) {
      selection.css({
        backgroundColor: "#f1f3f5",
        borderColor: "#ced4da",
        cursor: "not-allowed"
      })

      rendered.css({ color: "#6c757d" })
      arrow.css({ opacity: 0.5 })
    } else {
      selection.css({
        backgroundColor: "",
        borderColor: "",
        cursor: ""
      })

      rendered.css({ color: "" })
      arrow.css({ opacity: "" })
    }
  }
}

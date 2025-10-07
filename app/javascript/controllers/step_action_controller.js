import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hasAiActionCheckbox", "aiModelSelect", "aiModelLabel"]

  connect() {
    this.toggleAiModel()
  }

  toggleAiModel() {
    const enabled = this.hasAiActionCheckboxTarget.checked
    this.aiModelSelectTarget.disabled = !enabled    
    this.aiModelLabelTarget.classList.toggle("text-muted", !enabled)
  }
}

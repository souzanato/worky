import { Controller } from "@hotwired/stimulus"
import $ from "jquery"

export default class extends Controller {
  static values = {
    dropdownParent: String
  }

  connect() {
    const options = {
      width: "100%"
    }

    // Se dropdownParent foi especificado, usa ele
    if (this.hasDropdownParentValue) {
      options.dropdownParent = $(this.dropdownParentValue)
    } else {
      // Senão, tenta encontrar a modal pai automaticamente
      const modal = this.element.closest('.modal')
      if (modal) {
        options.dropdownParent = $(modal)
      }
    }

    $(this.element).select2(options)
  }

  disconnect() {
    if ($(this.element).data("select2")) {
      $(this.element).select2("destroy")
    }
  }
}
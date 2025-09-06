import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="action"
export default class extends Controller {
  static values = {
    action: Object
  }
  
  connect() {
  }
}

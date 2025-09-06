import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  copy(event) {
    event.preventDefault()
    navigator.clipboard.writeText(this.textValue).then(() => {
      this.showCopiedMessage()
    })
  }

  showCopiedMessage() {
    const element = this.element
    if (!element) return

    const original = element.innerHTML
    element.innerHTML = `${original} <span class="text-success ms-1">copied</span>`

    setTimeout(() => {
      element.innerHTML = original
    }, 1200)
  }
}

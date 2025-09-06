// app/javascript/controllers/workflow_builder_controller.js
import { Controller } from "@hotwired/stimulus"

// data-controller="workflow-builder"
export default class extends Controller {
  static targets = ["steps", "step", "actions", "action", "stepOrder", "actionOrder"]

  connect() {
    // Recalcula orders no load (útil no edit)
    this.recomputeStepOrders()
    this.stepTargets.forEach(step => this.recomputeActionOrders(step))
  }

  addStep(e) {
    e.preventDefault()
    const tpl = document.getElementById("step-template")
    if (!tpl) return
    this.stepsTarget.appendChild(tpl.content.cloneNode(true))
    this.recomputeStepOrders()
  }

  addAction(e) {
    e.preventDefault()
    const stepEl = e.target.closest("[data-workflow-builder-target='step']")
    const actionsWrap = stepEl?.querySelector("[data-workflow-builder-target='actions']")
    if (!actionsWrap) return
    const tpl = document.getElementById("action-template")
    actionsWrap.appendChild(tpl.content.cloneNode(true))
    this.recomputeActionOrders(stepEl)
  }


  removeStep(e) {
    e.preventDefault()
    const card = e.target.closest("[data-workflow-builder-target='step']")
    if (card) card.remove()
    this.recomputeStepOrders()
  }

  moveStepUp(e)  { this.moveCard(e, "step", -1) }
  moveStepDown(e){ this.moveCard(e, "step", +1) }

  removeAction(e) {
    e.preventDefault()
    const stepEl = e.target.closest("[data-workflow-builder-target='step']")
    const row = e.target.closest("[data-workflow-builder-target='action']")
    if (row) row.remove()
    this.recomputeActionOrders(stepEl)
  }

  moveActionUp(e)   { this.moveCard(e, "action", -1) }
  moveActionDown(e) { this.moveCard(e, "action", +1) }

  // -------- Helpers ----------
  moveCard(e, targetName, delta) {
    const node = e.target.closest(`[data-workflow-builder-target='${targetName}']`)
    if (!node) return
    const parent = node.parentElement
    const siblings = Array.from(parent.children).filter(n => n.matches(`[data-workflow-builder-target='${targetName}']`))
    const index = siblings.indexOf(node)
    const newIndex = index + delta
    if (newIndex < 0 || newIndex >= siblings.length) return

    // move
    if (delta < 0) {
      parent.insertBefore(node, siblings[newIndex])
    } else {
      parent.insertBefore(node, siblings[newIndex].nextSibling)
    }

    if (targetName === "step") {
      this.recomputeStepOrders()
    } else {
      const stepEl = e.target.closest("[data-workflow-builder-target='step']")
      this.recomputeActionOrders(stepEl)
    }
  }

  recomputeStepOrders() {
    this.stepTargets.forEach((stepEl, idx) => {
      const input = stepEl.querySelector("[data-workflow-builder-target='stepOrder']")
      if (input) input.value = idx + 1
      this.recomputeActionOrders(stepEl)
    })
  }

  recomputeActionOrders(stepEl) {
    const actions = stepEl.querySelectorAll("[data-workflow-builder-target='action']")
    actions.forEach((actEl, j) => {
      const input = actEl.querySelector("[data-workflow-builder-target='actionOrder']")
      if (input) input.value = j + 1
    })
  }

  replaceAllNames(fragment, placeholder, uid) {
    const walker = document.createTreeWalker(fragment, NodeFilter.SHOW_ELEMENT, null)
    const elems = []
    while (walker.nextNode()) elems.push(walker.currentNode)
    elems.forEach((el) => {
      // name=""
      if (el.name && el.name.includes(placeholder)) {
        el.name = el.name.replaceAll(placeholder, uid)
      }
      // id="" (opcional)
      if (el.id && el.id.includes(placeholder)) {
        el.id = el.id.replaceAll(placeholder, uid)
      }
      // for="" (labels)
      if (el.htmlFor && el.htmlFor.includes(placeholder)) {
        el.htmlFor = el.htmlFor.replaceAll(placeholder, uid)
      }
    })
  }

  extractStepUid(stepEl) {
    // tenta achar um name com [steps_attributes][UID]
    const anyInput = stepEl.querySelector("input[name*='workflow[steps_attributes]']")
    if (!anyInput) return null
    const m = anyInput.name.match(/workflow\[steps_attributes\]\[(.*?)\]/)
    return m ? m[1] : null
  }

  uid() {
    return `uid_${Math.random().toString(36).slice(2, 9)}`
  }
}

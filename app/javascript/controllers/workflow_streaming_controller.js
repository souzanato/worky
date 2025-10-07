import { Controller } from "@hotwired/stimulus"
import { WorkflowStreaming } from "../workflow_streaming"

export default class extends Controller {
  static values = { clientId: String, executionId: String }

  connect() {
    this.streaming = new WorkflowStreaming()
  }

  submit(event) {
    event.preventDefault()
    
    const formData = new FormData(this.element)
    const eventData = {
      action_id: formData.get('workflow_execution_event[action_id]'),
      input_data: formData.get('artifact[content]'),
      step_action: formData.get('workflow_execution_event[step_action]') || 'next'
    }
    
    const url = `/clients/${this.clientIdValue}/workflow_executions/${this.executionIdValue}/workflow_execution_events/stream`
    this.streaming.start(url, eventData)
  }
}
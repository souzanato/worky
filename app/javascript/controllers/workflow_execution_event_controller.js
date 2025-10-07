import { Controller } from "@hotwired/stimulus"
import { WorkflowStreaming } from "../workflow_streaming"

// Connects to data-controller="workflow-execution-event"
export default class extends Controller {
  static values = {
    action: Object,
    workflowExecution: Object
  }
  
  static targets = [
    'monacoEditor'
  ]

  connect() {
    // safe check se ai_action existe e se has_prompt_generator é true
    if (this.actionValue.has_prompt_generator === true) {
      this.createPromptGenerator()
    }
    this.streaming = new WorkflowStreaming()
  }

  // Interceptar submit para usar streaming
  submitWithStreaming(event) {
    event.preventDefault()
    
    const form = event.target.closest('form')
    const formData = new FormData(form)
    const clickedButton = event.currentTarget 
    
    // Capturar dados do form - estruturado como Rails espera
    const eventData = {
      workflow_execution_event: {
        action_id: formData.get('workflow_execution_event[action_id]'),
        input_data: formData.get('workflow_execution_event[input_data]'),
        step_action: clickedButton.value || 'prompt_it'
      }
    }
    
    // URL para streaming
    const execution = this.workflowExecutionValue
    const client_id = execution.client_id
    const execution_id = execution.id
    const url = `/clients/${client_id}/workflow_executions/${execution_id}/workflow_execution_events/stream`
    
    // Iniciar streaming com POST
    this.streaming.start(url, eventData)  // ← ou this.streaming.startWithPost(url, eventData)
  }

  updateMonaco(content, readOnly) {
    this.monacoEditorTarget.dispatchEvent(
      new CustomEvent("monaco:update", {
        bubbles: true,
        detail: { content, readOnly }
      })
    );
  }

  disconnect() {
    if (this.streaming) {
      this.streaming.cleanup()
    }
  }

  async createPromptGenerator() {
    try {
      // 🔒 Desabilita editor e mostra msg
      blockPage("Wait", "Prompt Generator is working...")
      this.updateMonaco("Aguarde o prompt generator...", true);

      const url = `/workflow_executions/${this.workflowExecutionValue.id}/actions/${this.actionValue.id}/prompt_generators`;

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
        },
        body: JSON.stringify({
          action_id: this.actionValue.id,
          step_id: this.actionValue.step.id,
          workload_id: this.actionValue.step.workload_id
        })
      });

      if (!response.ok) throw new Error(`HTTP error ${response.status}`);

      const data = await response.json();

      // ✅ Atualiza editor
      console.log(data.prompt)
      this.updateMonaco(data.prompt, false);
      unblockPage();
    } catch (error) {
      console.error("Erro ao criar Prompt Generator:", error);
      this.updateMonaco("Erro ao criar Prompt Generator", false);
    }
  }
}

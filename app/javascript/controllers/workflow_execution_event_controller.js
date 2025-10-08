// app/javascript/controllers/workflow_execution_event_controller.js
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
    this.subscribeToPromptChannel()

    this.boundHandlePromptGenerated = this.handlePromptGenerated.bind(this)
    this.boundHandlePromptError = this.handlePromptError.bind(this)

    document.addEventListener('prompt:generated', this.boundHandlePromptGenerated)
    document.addEventListener('prompt:error', this.boundHandlePromptError)

    // safe check se ai_action existe e se has_prompt_generator é true
    if (this.actionValue.has_prompt_generator === true) {
      this.createPromptGenerator()
    }
    this.streaming = new WorkflowStreaming()
  }

  subscribeToPromptChannel() {
    // O canal será subscrito automaticamente no HTML
  }

  handlePromptGenerated(event) {
    if (event.detail.actionId === this.actionValue.id) {
      this.updateMonaco(event.detail.prompt, false)
      unblockPage()
    }
  }

  handlePromptError(event) {
    if (event.detail.actionId === this.actionValue.id) {
      this.updateMonaco(`Error: ${event.detail.error}`, false)
      unblockPage()
      alert(`Error generating prompt: ${event.detail.error}`)
    }
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

    // Remove event listeners
    document.removeEventListener('prompt:generated', this.boundHandlePromptGenerated)
    document.removeEventListener('prompt:error', this.boundHandlePromptError)
  }

  async createPromptGenerator() {
    try {
      // 🔒 Desabilita editor e mostra msg
      blockPage("Wait", "Prompt Generator is working in background...")
      this.updateMonaco("⏳ Generating prompt... this may take a few minutes.", true);

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
      
      // Job enfileirado com sucesso
      console.log("Prompt generation started:", data.message);
      
      // A UI será atualizada via Turbo Stream quando o job terminar
      // (via handlePromptGenerated ou handlePromptError)
      
    } catch (error) {
      console.error("Erro ao criar Prompt Generator:", error);
      this.updateMonaco("❌ Error starting prompt generation", false);
      unblockPage();
    }
  }
}

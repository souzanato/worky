// app/javascript/workflow_streaming.js
export class WorkflowStreaming {
  constructor() {
    this.abortController = null
    this.buffer = ''
  }

  start(url, eventData) {
    // Usar seu blockPage existente
    window.blockPage()
    
    // Aguardar o blockUI aparecer
    setTimeout(() => {
      // Modificar o conteúdo da sua estrutura específica
      $('.blockui-title').text('Processando...')
      $('.blockui-description').html(`
        <div class="progress mt-2" style="height: 20px;">
          <div id="workflow-progress-bar" class="progress-bar progress-bar-striped progress-bar-animated" 
               style="width: 0%" role="progressbar">
            <span id="workflow-progress-text">0%</span>
          </div>
        </div>
        <div id="workflow-status-message" class="mt-2 small">Iniciando...</div>
      `)
      
      // Iniciar POST SSE
      this.connectSSE(url, eventData)
    }, 100)
  }

  async connectSSE(url, eventData) {
    // Cancela requisição anterior se existir
    if (this.abortController) {
      this.abortController.abort()
    }
    
    this.abortController = new AbortController()
    this.buffer = ''
    
    console.log('Connecting to:', url, eventData) // Debug
    
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify(eventData),
        signal: this.abortController.signal
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const reader = response.body.getReader()
      const decoder = new TextDecoder()

      while (true) {
        const { done, value } = await reader.read()
        
        if (done) break
        
        const chunk = decoder.decode(value, { stream: true })
        this.processChunk(chunk)
      }
      
    } catch (error) {
      if (error.name === 'AbortError') {
        console.log('Stream aborted')
      } else {
        console.error('Streaming error:', error)
        this.showError('Erro de conexão')
      }
    }
  }

  processChunk(chunk) {
    console.log('Received chunk:', chunk) // Debug
    
    // Adiciona chunk ao buffer
    this.buffer += chunk
    
    // Processa linhas completas
    const lines = this.buffer.split('\n')
    this.buffer = lines.pop() || '' // Guarda linha incompleta
    
    let currentEvent = null
    let currentData = ''
    
    lines.forEach(line => {
      if (line.startsWith('event: ')) {
        currentEvent = line.substring(7).trim()
      } else if (line.startsWith('data: ')) {
        currentData = line.substring(6)
      } else if (line.trim() === '') {
        // Linha vazia = fim do evento SSE
        if (currentEvent && currentData) {
          try {
            const data = JSON.parse(currentData)
            
            // Dispara os mesmos eventos que o EventSource disparava
            switch(currentEvent) {
              case 'status':
                console.log('SSE Status:', currentData) // Debug
                this.updateProgress(data.progress, data.message)
                break
              case 'complete':
                console.log('SSE Complete:', currentData) // Debug
                this.finish(data)
                break
              case 'error':
                console.log('SSE Error:', currentData) // Debug
                this.showError(data.error)
                break
            }
          } catch (e) {
            console.error('Error parsing SSE data:', e, currentData)
          }
        }
        currentEvent = null
        currentData = ''
      }
    })
  }

  updateProgress(progress, message) {
    console.log('Updating progress:', progress, message) // Debug
    
    if (progress) {
      $('#workflow-progress-bar').css('width', progress + '%')
      $('#workflow-progress-text').text(progress + '%')
    }
    
    $('.blockui-title').text(message || 'Processando...')
    $('#workflow-status-message').text(`Status: ${progress || 0}%`)
  }

  finish(data) {
    console.log('Finishing:', data) // Debug
    
    this.cleanup()
    $('.blockui-title').text('Concluído!')
    $('#workflow-progress-bar')
      .css('width', '100%')
      .removeClass('progress-bar-striped progress-bar-animated')
      .addClass('bg-success')
    $('#workflow-progress-text').text('100%')
    $('#workflow-status-message').text('Redirecionando...')
    
    setTimeout(() => {
      window.unblockPage()
      if (data.action === 'reload_page') {
        window.location.reload()
      } else if (data.redirect_url) {
        window.location.href = data.redirect_url
      }
    }, 1500)
  }

  showError(error) {
    console.log('Showing error:', error) // Debug
    
    this.cleanup()
    $('.blockui-title').text('Erro!')
    $('.blockui-description').html(`
      <div class="text-danger">
        <i class="fa fa-exclamation-triangle"></i>
        <div class="mt-2">${error}</div>
        <button class="btn btn-secondary btn-sm mt-3" onclick="$.unblockUI()">
          Fechar
        </button>
      </div>
    `)
  }

  cleanup() {
    if (this.abortController) {
      this.abortController.abort()
      this.abortController = null
    }
    this.buffer = ''
  }
}
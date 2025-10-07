// app/javascript/ai_record_streaming.js
export class AiRecordStreaming {
  constructor() {
    this.reader = null
    this.abortController = null
  }

  // ========= INÍCIO DO STREAMING JSON (sem arquivo)
  start(url, data) {
    blockPage("Processing", "Your request is being processed...")

    this.abortController = new AbortController()

    fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify(data),
      signal: this.abortController.signal
    })
      .then(response => {
        if (!response.ok) throw new Error(`HTTP error ${response.status}`)
        this.reader = response.body.getReader()
        const decoder = new TextDecoder()
        this.readStream(this.reader, decoder)
      })
      .catch(error => {
        console.error("Stream error:", error)
        unblockPage()
        if (error.name !== "AbortError") alert("Error processing request: " + error.message)
      })
  }

  // ========= INÍCIO DO STREAMING COM ARQUIVO (FormData)
  startWithFiles(url, formData) {
    blockPage("Uploading", "Uploading file...")

    this.abortController = new AbortController()

    fetch(url, {
      method: "POST",
      headers: {
        "Accept": "text/event-stream",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: formData,
      signal: this.abortController.signal
    })
      .then(response => {
        if (!response.ok) throw new Error(`HTTP error ${response.status}`)
        this.reader = response.body.getReader()
        const decoder = new TextDecoder()
        this.readStream(this.reader, decoder)
      })
      .catch(error => {
        console.error("Stream error:", error)
        unblockPage()
        if (error.name !== "AbortError") alert("Error uploading files: " + error.message)
      })
  }

  // ========= LEITURA DO STREAM SSE
  readStream(reader, decoder) {
    reader.read().then(({ done, value }) => {
      if (done) {
        console.log("Stream completed")
        unblockPage()
        return
      }

      const chunk = decoder.decode(value, { stream: true })
      const lines = chunk.split("\n")

      lines.forEach(line => {
        if (line.startsWith("data: ")) {
          const data = line.substring(6).trim()
          if (data === "") return

          try {
            const event = JSON.parse(data)
            this.handleEvent(event)
          } catch (e) {
            console.log("Non-JSON data:", data)
          }
        }
      })

      this.readStream(reader, decoder)
    }).catch(error => {
      if (error.name !== "AbortError") {
        console.error("Read stream error:", error)
        unblockPage()
        alert("Error reading stream: " + error.message)
      }
    })
  }

  // ========= TRATA EVENTOS DE PROGRESSO
  handleEvent(event) {
    console.log("Event received:", event)

    // Atualiza progresso
    if (event.progress !== undefined) {
      blockProgress(event.message || "Processing...", event.progress)
    }

    // Resultado das transcrições
    if (event.status === "transcriptions-result") {
      this.result = event.data
      
      // Mostra resumo se houver erros
      if (event.summary && event.summary.failed > 0) {
        console.warn(`⚠️ Summary: ${event.summary.successful} successful, ${event.summary.failed} failed`)
      }
      
      this.onTranscriptionResultReceived(this.result)
    }

    // ⚠️ NOVO: Erro em arquivo individual (não para o processo)
    if (event.status === "file_error") {
      console.error(`❌ File error [${event.file_index}/${event.total_files}]: ${event.file}`)
      console.error(`   Message: ${event.message}`)
      console.error(`   Class: ${event.error_class}`)
      console.error(`   Backtrace:`, event.backtrace)
      
      // Atualiza a mensagem mas continua processando
      blockProgress(
        `⚠️ Error in ${event.file}, continuing...`, 
        (event.file_index / event.total_files * 80 + 10)
      )
    }

    // Conclusão
    if (event.status === "completed") {
      const modal = bootstrap.Modal.getInstance(document.getElementById('aiRecordModal'))
      unblockPage()
      blockPage("✓ Processing completed!", "Closing this modal...")
      setTimeout(() => modal.hide(), 2000)
    }

    // Erro fatal (para todo o processo)
    if (event.status === "error") {
      unblockPage()
      
      console.error("❌ Fatal stream error:", {
        message: event.message,
        error_class: event.error_class
      })
      
      alert(`Fatal Error: ${event.message}\n\nCheck console for details.`)
    }
  }

  onTranscriptionResultReceived(result) {
    console.log("Processing transcription result:", result)
    
    // Separa sucessos e erros
    const successful = result.filter(item => item.status === "success")
    const failed = result.filter(item => item.status === "error")
    
    if (failed.length > 0) {
      console.warn(`⚠️ ${failed.length} file(s) failed:`)
      failed.forEach(item => {
        console.warn(`   - ${item.filename}: ${item.error}`)
      })
    }
    
    // Formata apenas os sucessos
    const formattedText = this.formatTranscriptions(successful)
    
    // Adiciona seção de erros se houver
    let errorSection = ''
    if (failed.length > 0) {
      errorSection = '\n\n## ⚠️ Failed Transcriptions\n\n'
      failed.forEach(item => {
        errorSection += `- **${item.filename}**: ${item.error}\n`
      })
    }
    
    // Atualiza o Monaco Editor
    this.appendToMonaco(formattedText + errorSection)
  }

  formatTranscriptions(transcriptions) {
    return transcriptions
      .filter(item => item.status === "success") // Garante que só formata sucessos
      .map((item, index) => {
        const number = index + 1
        const filename = item.filename
        const text = item.result.text
        
        return `## ${number}. ${filename}\n\n${text}\n\n`
      })
      .join('---\n\n')
  }

  updateMonaco(content, readOnly = false) {
    const element = document.getElementById('action-content')

    if (element) {
      element.dispatchEvent(new CustomEvent('monaco:update', {
        detail: { content, readOnly }
      }))
      console.log("Monaco updated with new content")
    } else {
      console.warn('Monaco editor element not found:', this.monacoElementId)
    }
  }

  getMonacoCurrentContent() {
    const hiddenInput = document.getElementById('workflow_execution_event_input_data')
    return hiddenInput?.value || ''
  }

  appendToMonaco(newContent) {
    // Pega o conteúdo atual
    const currentContent = this.getMonacoCurrentContent()
    
    // Concatena com separador se já tiver conteúdo
    const separator = currentContent.trim() ? '\n\n---\n\n' : ''
    const fullContent = currentContent + separator + newContent
    
    // Atualiza o Monaco
    this.updateMonaco(fullContent, false)
  }

  // ========= LIMPEZA / CANCELAMENTO
  cleanup() {
    if (this.abortController) this.abortController.abort()
    if (this.reader) this.reader.cancel()
    unblockPage()
  }
}

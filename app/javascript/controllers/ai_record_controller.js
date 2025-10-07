import { Controller } from "@hotwired/stimulus"
import { AiRecordStreaming } from "../ai_record_streaming"

export default class extends Controller {
  static targets = ["youtubeLink", "urlLink", "audioFiles"]

  connect() {
    this.element.setAttribute("novalidate", "novalidate")
    this.streaming = new AiRecordStreaming()
  }

  disconnect() {
    if (this.streaming) this.streaming.cleanup()
  }

  // =============================
  // GENERIC URL VALIDATION
  // =============================
  validateUrl(input, label) {
    const value = (input.value || "").trim()
    const regex = /^(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w\.-]*)*\/?$/i

    if (!value) return this.setError(input, `${label} is required`)
    if (!regex.test(value)) return this.setError(input, `Please enter a valid ${label}`)
    return this.clearError(input)
  }

  // =============================
  // FILE VALIDATION (Whisper-compatible)
  // =============================
  validateFiles(input) {
    const files = input.files
    if (!files || !files.length)
      return this.setError(input, "Please select at least one file")

    // Whisper-compatible formats
    const allowed = ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm"]
    const maxSize = 100 * 1024 * 1024 // 100MB

    for (const file of files) {
      const ext = file.name.split(".").pop().toLowerCase()
      if (!allowed.includes(ext))
        return this.setError(input, `Invalid file: ${file.name}`)
      if (file.size > maxSize)
        return this.setError(input, `File too large: ${file.name} (max 100MB)`)
    }

    return this.clearError(input)
  }

  // =============================
  // ERROR HANDLING HELPERS
  // =============================
  setError(input, message) {
    input.classList.add("is-invalid")
    const feedback = input.parentElement.querySelector(".invalid-feedback")
    if (feedback) {
      feedback.textContent = message
      feedback.style.display = "block"
    }
    return false
  }

  clearError(input) {
    input.classList.remove("is-invalid")
    const feedback = input.parentElement.querySelector(".invalid-feedback")
    if (feedback) feedback.style.display = "none"
    return true
  }

  // =============================
  // FORM SUBMISSION
  // =============================
  submit(event) {
    event.preventDefault()
    let isValid = true

    if (this.hasYoutubeLinkTarget)
      isValid = this.validateUrl(this.youtubeLinkTarget, "YouTube link") && isValid

    if (this.hasUrlLinkTarget)
      isValid = this.validateUrl(this.urlLinkTarget, "Web page URL") && isValid

    if (this.hasAudioFilesTarget)
      isValid = this.validateFiles(this.audioFilesTarget) && isValid

    if (!isValid) return false

    this.submitWithStreaming(event)
  }

  submitWithStreaming(event) {
    const form = event.target
    const formData = new FormData(form)

    const files = formData.getAll("ai_record[source_files][]").filter(f => f instanceof File)
    console.log("Files detected:", files)

    if (files.length > 0) {
      // ✅ mantém FormData, que inclui os hidden fields certos
      this.streaming.startWithFiles(form.action, formData)
    } else {
      // ✅ remove duplicações e envia JSON limpo
      const cleaned = {}
      for (const [key, value] of formData.entries()) {
        // remove o prefixo "ai_record[" e o sufixo "]"
        const match = key.match(/^ai_record\[(.+)\]$/)
        if (match) cleaned[match[1]] = value
      }

      this.streaming.start(form.action, { ai_record: cleaned })
    }
  }
}

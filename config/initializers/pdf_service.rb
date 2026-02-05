Rails.application.config.pdf_service = {
  url: ENV.fetch("PDF_SERVICE_URL", "http://localhost:8000"),
  timeout: ENV.fetch("PDF_SERVICE_TIMEOUT", 60).to_i
}

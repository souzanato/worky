// app/javascript/turbo_listener.js
import { Turbo } from "@hotwired/turbo-rails"

let activeTurboRequests = 0

document.addEventListener("turbo:before-fetch-request", (event) => {
  const fetchOptions = event.detail.fetchOptions || {}
  const headers = fetchOptions.headers || {}
  const accepts = headers["Accept"] || headers["accept"] || ""
  const method = (fetchOptions.method || "GET").toUpperCase()

  // 🔑 ignora prefetch de hover (GET sem body e sem frame target)
  const isPrefetchHover =
    method === "GET" &&
    !fetchOptions.body &&
    !fetchOptions.target

  if (isPrefetchHover) return

  if (accepts.includes("turbo-stream") || accepts.includes("text/html")) {
    activeTurboRequests++
    if (activeTurboRequests === 1) {
      blockPage()
    }
  }
})

document.addEventListener("turbo:before-fetch-response", (event) => {
  const response = event.detail.fetchResponse
  const contentType = response.response.headers.get("Content-Type") || ""

  if (contentType.includes("turbo-stream") || contentType.includes("text/html")) {
    activeTurboRequests--
    if (activeTurboRequests <= 0) {
      activeTurboRequests = 0
      unblockPage()
    }
  }
})

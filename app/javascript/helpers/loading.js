// Mostra overlay genérico com spinner e mensagem
export function blockPage(title = "Loading", description = "Please wait...") {
  const modalZIndex = 1050
  const overlayZIndex = modalZIndex + 100
  const messageZIndex = overlayZIndex + 10

  $.blockUI({
    message: `
      <div class="blockui-box text-center p-4">
        <div class="spinner-border text-primary mb-3" role="status" style="width: 3rem; height: 3rem;">
          <span class="visually-hidden">Loading...</span>
        </div>
        <div class="blockui-title h5 fw-bold mb-1">${title}</div>
        <div class="blockui-description text-muted">${description}</div>
      </div>
    `,
    css: {
      border: "none",
      backgroundColor: "transparent",
      color: "#333",
      zIndex: messageZIndex
    },
    overlayCSS: {
      backgroundColor: "rgba(255, 255, 255, 0.9)",
      opacity: 1,
      cursor: "wait",
      zIndex: overlayZIndex
    },
    baseZ: modalZIndex + 100
  })

  document.body.style.overflow = "hidden"
}

// Mostra overlay com barra de progresso
export function blockProgress(title = "Processing...", progress = 0, subtitle = "Please wait...") {
  const modalZIndex = 1050
  const overlayZIndex = modalZIndex + 100
  const messageZIndex = overlayZIndex + 10

  const progressHtml = `
    <div class="blockui-box text-center p-4" style="min-width: 420px; max-width: 600px; margin: 0 auto;">
      <div class="mb-3 w-100">
        <div class="progress" style="height: 22px; background-color: #e9ecef; border-radius: 10px; overflow: hidden;">
          <div class="progress-bar bg-primary fw-bold text-white"
               role="progressbar"
               style="width: ${progress}%; transition: width 0.3s; line-height: 22px;"
               aria-valuenow="${progress}" aria-valuemin="0" aria-valuemax="100">
            ${progress}%
          </div>
        </div>
      </div>
      <div class="blockui-title h5 fw-bold mb-1">${title}</div>
      <div class="blockui-description text-muted">${subtitle}</div>
    </div>
  `

  $.blockUI({
    message: progressHtml,
    css: {
      border: "none",
      backgroundColor: "transparent",
      color: "#333",
      zIndex: messageZIndex
    },
    overlayCSS: {
      backgroundColor: "rgba(255, 255, 255, 0.9)",
      opacity: 1,
      cursor: "wait",
      zIndex: overlayZIndex
    },
    baseZ: modalZIndex + 100
  })

  document.body.style.overflow = "hidden"
}

// Remove overlay
export function unblockPage() {
  $.unblockUI()
  document.body.style.overflow = ""
}

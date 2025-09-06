export function blockPage(title = "Loading", description = "Please wait...") {
  $.blockUI({
    message: `
      <div class="blockui-box">
        <div class="blockui-spinner"></div>
        <div class="blockui-title">${title}</div>
        <div class="blockui-description">${description}</div>
      </div>
    `,
    css: {
      border: "none",
      backgroundColor: "transparent"
    },
    overlayCSS: {
      backgroundColor: "#fff",
      opacity: 0.85,
      cursor: "wait"
    },
    baseZ: 9999
  });
}

export function unblockPage() {
  $.unblockUI();
}

// ============================================================================
// 🧠 PACE.JS + TURBO + COLOR ADMIN PATCH (v2 modular)
// Ignora WebSockets do ActionCable, sincroniza com Turbo, elimina Illegal Invocation
// ============================================================================

window.paceOptions = {
  restartOnPushState: false,
  restartOnRequestAfter: 300,
  ajax: {
    trackWebSockets: false,
    ignoreURLs: [/^wss?:\/\//, /cable/, /action_cable/]
  },
  elements: {
    selectors: ['.main-content', '.page-content']
  }
};

// 🔁 Integrar com eventos do Turbo
const restartPace = () => window.Pace && window.Pace.restart();
const stopPace = () => window.Pace && window.Pace.stop();

document.addEventListener('turbo:visit', restartPace);
document.addEventListener('turbo:before-fetch-request', restartPace);

document.addEventListener('turbo:before-fetch-response', () => {
  if (window.Pace && !window.Pace.running) stopPace();
});

document.addEventListener('turbo:load', () => {
  if (window.Pace && window.Pace.running) {
    setTimeout(stopPace, 200);
  }
});

// 💅 Estilo opcional para suavizar o visual (se quiser inline)
const style = document.createElement("style");
style.innerHTML = `
  .pace .pace-progress {
    background: #4f81e1 !important;
    height: 3px !important;
  }
  .pace .pace-progress-inner {
    box-shadow: 0 0 10px #4f81e1, 0 0 5px #4f81e1;
  }
`;
document.head.appendChild(style);

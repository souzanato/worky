// Navega imediatamente ao clicar nos links da partial, antes do blur disparar CSV
function bindDeviseInstantNav() {
  // captura mousedown (dispara antes do blur/click) só em links marcados
  document.addEventListener('mousedown', function (e) {
    const link = e.target.closest('.devise-links a.devise-link');
    if (!link) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    // Turbo respeita location.assign; se preferir Turbo.visit, pode trocar
    window.location.assign(link.href);
  }, true);

  // acessibilidade: Enter/Espaço via teclado também navega imediato
  document.addEventListener('keydown', function (e) {
    if (!(e.key === 'Enter' || e.key === ' ')) return;
    const link = e.target.closest('.devise-links a.devise-link');
    if (!link) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    window.location.assign(link.href);
  }, true);
}

document.addEventListener('turbo:load', bindDeviseInstantNav);
document.addEventListener('DOMContentLoaded', bindDeviseInstantNav);

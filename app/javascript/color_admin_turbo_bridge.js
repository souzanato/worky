// app/javascript/color_admin_turbo_bridge.js

(function () {
  if (window.__colorAdminTurboBridgeBound) return;
  window.__colorAdminTurboBridgeBound = true;

  let __loaderTimer = null;

  function killLoadersNow() {
    document.querySelectorAll('#app-content-loader').forEach(el => el.remove());
    document.body.classList.remove('app-content-loading');
    document.querySelectorAll('.app-loader').forEach(el => {
      el.classList.remove('fading'); el.classList.add('loaded');
      setTimeout(() => { try { el.remove(); } catch(e){} }, 300);
    });
  }
  function killLoadersDelayed(ms = 1000) {
    if (__loaderTimer) clearTimeout(__loaderTimer);
    __loaderTimer = setTimeout(() => { __loaderTimer = null; killLoadersNow(); }, ms);
  }

  // === util: reinit do tema + abrir pais com filho ativo
  function reinitThemeAndSidebar() {
    // dá um tick pro DOM assentar
    requestAnimationFrame(() => {
      if (window.App) {
        if (typeof App.restartGlobalFunction === 'function') App.restartGlobalFunction();
        // Color Admin costuma ter init() que liga tudo; alguns builds têm initSidebar()
        if (typeof App.initSidebar === 'function') App.initSidebar();
        else if (typeof App.init === 'function') App.init();
        if (typeof App.initComponent === 'function') App.initComponent();
      }

      // Garante que pais com filho ativo fiquem abertos
      document.querySelectorAll('.menu .menu-item.has-sub').forEach(parent => {
        const hasActiveChild = parent.querySelector(':scope > .menu-submenu .menu-item.active');
        if (hasActiveChild) parent.classList.add('active');
      });
    });
  }

  // === fallback: delegação de clique pro collapse (resiliente a Turbo)
  function bindSidebarDelegationOnce() {
    if (window.__sidebarDelegationBound) return;
    window.__sidebarDelegationBound = true;

    document.addEventListener('click', (e) => {
      const link = e.target.closest('.menu .menu-item.has-sub > .menu-link');
      if (!link) return;

      // Se o tema já usar data-toggle específico, você pode checar e deixar passar:
      // if (link.matches('[data-toggle], [data-bs-toggle]')) return;

      e.preventDefault();
      const parent = link.closest('.menu-item.has-sub');

      // acordeon: fecha irmãos
      const siblings = parent.parentElement?.querySelectorAll(':scope > .menu-item.has-sub.active') || [];
      siblings.forEach(el => { if (el !== parent) el.classList.remove('active'); });

      parent.classList.toggle('active');
    }, true);
  }

  // === Turbo hooks
  document.addEventListener('turbo:render', () => {
    if (window.Pace?.restart) Pace.restart();
    reinitThemeAndSidebar();
    bindSidebarDelegationOnce();
    killLoadersDelayed(500);
  });

  document.addEventListener('turbo:load', () => {
    reinitThemeAndSidebar();
    bindSidebarDelegationOnce();
    killLoadersDelayed(500);
  });

  document.addEventListener('turbo:frame-load', () => {
    reinitThemeAndSidebar();
    killLoadersDelayed(500);
  });

  document.addEventListener('turbo:before-cache', () => {
    if (__loaderTimer) { clearTimeout(__loaderTimer); __loaderTimer = null; }
    killLoadersNow();

    // limpa tooltips/popovers
    if (window.bootstrap) {
      document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => bootstrap.Tooltip.getInstance(el)?.dispose());
      document.querySelectorAll('[data-bs-toggle="popover"]').forEach(el => bootstrap.Popover.getInstance(el)?.dispose());
    }
    // fecha modais e backdrops
    document.querySelectorAll('.modal.show').forEach(m => m.classList.remove('show'));
    document.body.classList.remove('modal-open');
    document.querySelectorAll('.modal-backdrop').forEach(b => b.remove());

    // flutuantes do tema
    ['#app-sidebar-float-submenu','.jvectormap-tip','.daterangepicker','.nvtooltip','.sp-container','.lightbox','.lightboxOverlay','#gritter-notice-wrapper']
      .forEach(sel => document.querySelectorAll(sel).forEach(el => el.remove()));
  });

  if (window.Pace?.on) Pace.on('done', () => killLoadersDelayed(500));
})();

// ClientSideValidations + Bootstrap 5 (form-floating friendly)
// - Mantém label grudado no input (ordem exigida pelo .form-floating)
// - Insere o .invalid-feedback como IRMÃO do .form-floating (após ele)
(function() {
  if (!window.ClientSideValidations) return;

  window.ClientSideValidations.formBuilders['ActionView::Helpers::FormBuilder'] = {
    add: function(element, settings, message) {
      const $el = $(element);

      // marca o input
      $el.addClass('is-invalid');

      // Se estiver em .form-floating, feedback vai DEPOIS do wrapper
      const $floating = $el.closest('.form-floating');
      let $fb;

      if ($floating.length) {
        $fb = $floating.next('.invalid-feedback');
        if ($fb.length === 0) {
          $fb = $('<div class="invalid-feedback"></div>');
          $floating.after($fb);
        }
      } else {
        // fallback para campos normais (sem floating)
        const $wrap = $el.closest('.mb-3, .field');
        $fb = $wrap.children('.invalid-feedback');
        if ($fb.length === 0) {
          $fb = $('<div class="invalid-feedback"></div>');
          $el.after($fb);
        }
      }

      $fb.text(message).show();
    },

    remove: function(element, settings) {
      const $el = $(element);
      $el.removeClass('is-invalid');

      const $floating = $el.closest('.form-floating');
      let $fb;
      if ($floating.length) {
        $fb = $floating.next('.invalid-feedback');
      } else {
        $fb = $el.closest('.mb-3, .field').children('.invalid-feedback');
      }
      $fb.text('').hide();
    }
  };
})();

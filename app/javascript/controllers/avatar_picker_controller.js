// app/javascript/controllers/avatar_picker_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["option", "box"];

  connect() {
    this.update();
    // permitir clique no box de imagem também
    this.optionTargets.forEach((opt) => {
      const box = opt.querySelector('[data-avatar-picker-target="box"]');
      if (box) {
        box.addEventListener("click", () => {
          const input = opt.querySelector('input[type="radio"]');
          if (input) {
            input.checked = true;
            input.dispatchEvent(new Event("change", { bubbles: true }));
          }
        });
      }
    });
  }

  select() { this.update(); }

  update() {
    this.optionTargets.forEach((opt) => {
      const input = opt.querySelector('input[type="radio"]');
      const box = opt.querySelector('[data-avatar-picker-target="box"]');
      if (!box || !input) return;

      box.classList.remove("avatar-selected");

      if (input.checked) {
        box.classList.add("avatar-selected");
      }
    });
  }
}

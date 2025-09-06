// app/javascript/controllers/monaco_controller.js
import { Controller } from "@hotwired/stimulus";
import React from "react";
import ReactDOM from "react-dom/client";
import MonacoEditor from "../components/MonacoEditor";

export default class extends Controller {
  static values = {
    language: String,
    theme: String,
    height: String,
    hiddenFieldId: String,
    initial: String,
    placeholder: String
  }

  connect() {
    this.root = ReactDOM.createRoot(this.element);

    this.renderEditor({
      value: this.initialValue,
      readOnly: false
    });

    // 👂 Escuta os updates vindos do Stimulus externo
    this.element.addEventListener("monaco:update", this.handleUpdate);
  }

  disconnect() {
    this.element.removeEventListener("monaco:update", this.handleUpdate);
    this.root?.unmount();
  }

  handleUpdate = (event) => {
    const { content, readOnly } = event.detail;
    this.renderEditor({ value: content, readOnly });
  }

  renderEditor({ value, readOnly }) {
    this.root.render(
      <MonacoEditor
        value={value}
        readOnly={readOnly}
        language={this.languageValue}
        theme={this.themeValue}
        hiddenFieldId={this.hiddenFieldIdValue}
        placeholder={this.placeholderValue || "Digite aqui"}
        onChange={(val) => {
          if (this.hiddenFieldIdValue) {
            const hidden = document.querySelector(`#${this.hiddenFieldIdValue}`);
            if (hidden) hidden.value = val;
          }
        }}
      />
    );
  }

  toggleFullscreen(isFullscreen = true) {
    const event = new CustomEvent("monaco-fullscreen-toggle", {
      detail: { fullscreen: isFullscreen }
    });
    window.dispatchEvent(event);
  }
}

import React, { useRef, useState, useEffect } from "react";
import Editor from "@monaco-editor/react";
import themeData from "monaco-themes/themes/iPlastic.json";

export default function MonacoEditor({
  value,
  onChange,
  language,
  theme,
  hiddenFieldId,
  placeholder,
  readOnly = false
}) {
  const editorRef = useRef(null);
  const wrapperRef = useRef(null);
  const [isMaximized, setIsMaximized] = useState(false);

  const handleEditorDidMount = (editor, monaco) => {
    editorRef.current = editor;

    monaco.editor.defineTheme("iPlastic", themeData);
    monaco.editor.setTheme("iPlastic");

    editor.updateOptions({
      dropIntoEditor: { enabled: false },
      readOnly
    });

    setTimeout(() => {
      editor.layout();
    }, 0);

    // === DROP personalizado ===
    const domNode = editor.getDomNode();
    domNode.addEventListener("drop", (event) => {
      event.preventDefault();
      event.stopPropagation();

      const text = event.dataTransfer.getData("text/plain") || "";
      const x = event.clientX;
      const y = event.clientY;
      const target = editor.getTargetAtClientPoint(x, y);
      const position = target?.position || editor.getPosition();

      editor.focus();

      editor.executeEdits("", [
        {
          range: new monaco.Range(
            position.lineNumber,
            position.column,
            position.lineNumber,
            position.column
          ),
          text: text
        }
      ]);

      editor.setPosition({
        lineNumber: position.lineNumber,
        column: position.column + text.length
      });
    });

    // === PLACEHOLDER customizado ===
    const placeholderWidget = {
      domNode: null,
      getId: () => "placeholder.widget",
      getDomNode: () => {
        if (!placeholderWidget.domNode) {
          const div = document.createElement("div");
          div.style.opacity = "0.4";
          div.style.fontStyle = "italic";
          div.style.pointerEvents = "none";
          div.style.padding = "4px";
          div.style.position = "fixed";
          div.style.top = "12px";
          div.style.left = "12px";
          div.style.zIndex = "1";
          div.style.background = "transparent";
          div.style.whiteSpace = "nowrap";
          div.style.maxWidth = "80%";
          div.textContent = placeholder || "Digite algo aqui...";
          placeholderWidget.domNode = div;
        }
        return placeholderWidget.domNode;
      },
      getPosition: () => {
        const model = editor.getModel();
        if (!model || model.getValue() !== "") return null;
        return {
          position: { lineNumber: 1, column: 1 },
          preference: [monaco.editor.ContentWidgetPositionPreference.EXACT]
        };
      }
    };

    const updatePlaceholder = () => {
      const model = editor.getModel();
      if (model.getValue() === "") {
        editor.addContentWidget(placeholderWidget);
      } else {
        editor.removeContentWidget(placeholderWidget);
      }
    };

    editor.onDidChangeModelContent(updatePlaceholder);
    editor.onDidFocusEditorText(updatePlaceholder);
    editor.onDidBlurEditorText(updatePlaceholder);

    updatePlaceholder();
  };

  // === ESCUTA monaco:update vindo do Stimulus ===
  useEffect(() => {
    const handler = (e) => {
      const { content, readOnly } = e.detail;
      if (editorRef.current) {
        editorRef.current.setValue(content || "");
        editorRef.current.updateOptions({ readOnly });

        // 🔑 Atualiza hidden input junto
        if (hiddenFieldId) {
          const hiddenInput = document.getElementById(hiddenFieldId);
          if (hiddenInput) hiddenInput.value = content || "";
        }
      }
    };

    const node = wrapperRef.current;
    node?.addEventListener("monaco:update", handler);

    return () => node?.removeEventListener("monaco:update", handler);
  }, [hiddenFieldId]);

  // 🔑 sempre sincroniza hidden input quando `value` mudar externamente
  useEffect(() => {
    if (hiddenFieldId) {
      const hiddenInput = document.getElementById(hiddenFieldId);
      if (hiddenInput) hiddenInput.value = value || "";
    }
  }, [value, hiddenFieldId]);

  const toggleMaximize = () => {
    const nextState = !isMaximized;
    setIsMaximized(nextState);

    document.body.style.overflow = nextState ? "hidden" : "";
  };

  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === "Escape" && isMaximized) {
        setIsMaximized(false);
        document.body.style.overflow = "";
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [isMaximized]);

  useEffect(() => {
    setTimeout(() => {
      if (editorRef.current) {
        editorRef.current.layout();
      }
    }, 50);
  }, [isMaximized]);

  return (
    <div
      ref={wrapperRef}
      style={{
        position: isMaximized ? "fixed" : "relative",
        top: isMaximized ? 0 : "auto",
        left: isMaximized ? 0 : "auto",
        zIndex: isMaximized ? 9999 : "1",
        width: isMaximized ? "100vw" : "100%",
        height: isMaximized ? "100vh" : 500,
        background: "white",
        boxShadow: isMaximized ? "0 0 0 100vmax rgba(0,0,0,0.4)" : "none"
      }}
    >
      {/* Botão flutuante com ícone */}
      <button
        type="button"
        onClick={toggleMaximize}
        style={{
          position: "absolute",
          top: "8px",
          right: "8px",
          zIndex: 10000,
          background: "#fff",
          border: "1px solid #ccc",
          borderRadius: "4px",
          padding: "4px 8px",
          fontSize: "1rem",
          cursor: "pointer"
        }}
      >
        <i className={`fas ${isMaximized ? "fa-compress" : "fa-expand"}`}></i>
      </button>

      <Editor
        height="100%"
        width="100%"
        language={language || "markdown"}
        value={value?.replace(/\n+$/, "") || ""}
        onMount={handleEditorDidMount}
        onChange={(val) => {
          if (hiddenFieldId) {
            const hiddenInput = document.getElementById(hiddenFieldId);
            if (hiddenInput) hiddenInput.value = val || "";
          }
          if (onChange) onChange(val);
        }}
        options={{
          readOnly,
          minimap: { enabled: false },
          fontSize: 14,
          wordWrap: "on",
          lineNumbers: "off",
          scrollBeyondLastLine: false,
          mouseWheelScrollSensitivity: 0,
          scrollbar: {
            vertical: "auto",
            alwaysConsumeMouseWheel: false
          },
          overviewRulerLanes: 0,
          automaticLayout: true
        }}
      />
    </div>
  );
}

// CodeMirror 6 editor — loaded from CDN for simplicity.
// The WKWebView loads this from file:// but can fetch remote ES modules.

const CDN = "https://esm.sh";
const CM_VERSION = "6.65.7";

async function loadModules() {
  const [
    { EditorView, basicSetup },
    { EditorState },
    { oneDark },
    { keymap },
    { indentWithTab },
    { javascript },
    { python },
    { html },
    { css },
    { json },
    { markdown },
    { rust },
    { cpp },
    { java },
    { sql },
    { xml },
    { yaml },
    { StreamLanguage },
    { go },
    { ruby },
    { shell },
    { swift },
    { lua },
    { perl },
    { r: rLang },
    { toml },
    { zig },
    cmLang,
  ] = await Promise.all([
    import(`${CDN}/codemirror@${CM_VERSION}`),
    import(`${CDN}/@codemirror/state@6`),
    import(`${CDN}/@codemirror/theme-one-dark@6`),
    import(`${CDN}/@codemirror/view@6`),
    import(`${CDN}/@codemirror/commands@6`),
    import(`${CDN}/@codemirror/lang-javascript@6`),
    import(`${CDN}/@codemirror/lang-python@6`),
    import(`${CDN}/@codemirror/lang-html@6`),
    import(`${CDN}/@codemirror/lang-css@6`),
    import(`${CDN}/@codemirror/lang-json@6`),
    import(`${CDN}/@codemirror/lang-markdown@6`),
    import(`${CDN}/@codemirror/lang-rust@6`),
    import(`${CDN}/@codemirror/lang-cpp@6`),
    import(`${CDN}/@codemirror/lang-java@6`),
    import(`${CDN}/@codemirror/lang-sql@6`),
    import(`${CDN}/@codemirror/lang-xml@6`),
    import(`${CDN}/@codemirror/lang-yaml@6`),
    import(`${CDN}/@codemirror/language@6`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/go`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/ruby`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/shell`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/swift`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/lua`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/perl`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/r`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/toml`),
    import(`${CDN}/@codemirror/legacy-modes@6/mode/z80`), // placeholder for zig — closest available
    import(`${CDN}/@codemirror/language@6`),
  ]);

  // Language map
  const languages = {
    javascript: () => javascript({ jsx: false }),
    jsx: () => javascript({ jsx: true, typescript: false }),
    typescript: () => javascript({ jsx: false, typescript: true }),
    tsx: () => javascript({ jsx: true, typescript: true }),
    python: () => python(),
    html: () => html(),
    css: () => css(),
    json: () => json(),
    markdown: () => markdown(),
    rust: () => rust(),
    c: () => cpp(),
    cpp: () => cpp(),
    csharp: () => cpp(), // close enough syntax highlighting
    java: () => java(),
    sql: () => sql(),
    xml: () => xml(),
    yaml: () => yaml(),
    go: () => StreamLanguage.define(go),
    ruby: () => StreamLanguage.define(ruby),
    shell: () => StreamLanguage.define(shell),
    swift: () => StreamLanguage.define(swift),
    lua: () => StreamLanguage.define(lua),
    perl: () => StreamLanguage.define(perl),
    r: () => StreamLanguage.define(rLang),
    toml: () => StreamLanguage.define(toml),
    dart: () => javascript(), // fallback
    kotlin: () => java(),     // fallback
    scala: () => java(),      // fallback
    objectivec: () => cpp(),  // fallback
    php: () => html(),        // fallback (PHP embedded in HTML)
    zig: () => StreamLanguage.define(zig), // approximate
    plain: () => [],
  };

  function getLanguageExtension(lang) {
    const factory = languages[lang];
    if (!factory) return [];
    const ext = factory();
    return Array.isArray(ext) ? ext : [ext];
  }

  // Compartments for dynamic reconfiguration
  const { Compartment } = await import(`${CDN}/@codemirror/state@6`);
  const languageCompartment = new Compartment();
  const themeCompartment = new Compartment();
  const readOnlyCompartment = new Compartment();

  // Notify Swift when content changes (debounced)
  let changeTimer = null;
  const updateListener = EditorView.updateListener.of((update) => {
    if (update.docChanged) {
      clearTimeout(changeTimer);
      changeTimer = setTimeout(() => {
        window.webkit?.messageHandlers?.contentChanged?.postMessage(
          update.state.doc.toString()
        );
      }, 300);
    }
  });

  const state = EditorState.create({
    doc: "",
    extensions: [
      basicSetup,
      keymap.of([indentWithTab]),
      languageCompartment.of([]),
      themeCompartment.of(oneDark),
      readOnlyCompartment.of(EditorState.readOnly.of(false)),
      updateListener,
      EditorView.theme({
        "&": { fontSize: "13px", fontFamily: "SF Mono, Menlo, Monaco, monospace" },
      }),
    ],
  });

  const view = new EditorView({
    state,
    parent: document.getElementById("editor"),
  });

  // Global API for Swift
  window.setContent = (content) => {
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: content },
    });
  };

  window.getContent = () => view.state.doc.toString();

  window.setLanguage = (lang) => {
    view.dispatch({
      effects: languageCompartment.reconfigure(getLanguageExtension(lang)),
    });
  };

  window.setTheme = (theme) => {
    // For now only oneDark is bundled; extend as needed
    view.dispatch({
      effects: themeCompartment.reconfigure(oneDark),
    });
  };

  window.setReadOnly = (readOnly) => {
    view.dispatch({
      effects: readOnlyCompartment.reconfigure(
        EditorState.readOnly.of(readOnly)
      ),
    });
  };

  window.focusEditor = () => {
    view.focus();
  };

  // Notify Swift that editor is ready
  window.webkit?.messageHandlers?.editorReady?.postMessage(true);
}

loadModules().catch((err) => {
  console.error("Failed to load CodeMirror:", err);
  document.getElementById("editor").textContent =
    "Failed to load editor: " + err.message;
});

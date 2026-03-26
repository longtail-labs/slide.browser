import Foundation
import WebKit

/// ViewModel that manages a CodeMirror 6 editor inside a WKWebView.
/// Communicates with JS via `evaluateJavaScript` and receives callbacks via `WKScriptMessageHandler`.
@MainActor
public final class CodeMirrorVM: NSObject, ObservableObject {
    public let webView: WKWebView
    @Published public var isReady = false
    @Published public var isDirty = false

    private var onContentChange: ((String) -> Void)?
    private var pendingContent: String?
    private var pendingLanguage: CodeLanguage?
    private var pendingTheme: CodeTheme?

    public init(onContentChange: ((String) -> Void)? = nil) {
        self.onContentChange = onContentChange

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let userContent = WKUserContentController()
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        super.init()

        userContent.add(self, name: "contentChanged")
        userContent.add(self, name: "editorReady")
    }

    // MARK: - Load

    /// Load the editor HTML from the bundle.
    public func loadEditor() {
        guard let bundleURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "web.bundle") else {
            print("[CodeMirrorVM] index.html not found in web.bundle")
            return
        }
        let bundleDir = bundleURL.deletingLastPathComponent()
        webView.loadFileURL(bundleURL, allowingReadAccessTo: bundleDir)
    }

    // MARK: - Content

    public func setContent(_ content: String) {
        guard isReady else {
            pendingContent = content
            return
        }
        let escaped = escapeForJS(content)
        JavascriptFunction("window.setContent(\(escaped))").evaluate(in: webView)
        isDirty = false
    }

    public func getContent() async -> String {
        guard isReady else { return pendingContent ?? "" }
        do {
            let result = try await JavascriptFunction("window.getContent()").evaluate(in: webView)
            return result as? String ?? ""
        } catch {
            print("[CodeMirrorVM] getContent error: \(error)")
            return ""
        }
    }

    // MARK: - Language & Theme

    public func setLanguage(_ language: CodeLanguage) {
        guard isReady else {
            pendingLanguage = language
            return
        }
        JavascriptFunction("window.setLanguage('\(language.rawValue)')").evaluate(in: webView)
    }

    public func setTheme(_ theme: CodeTheme) {
        guard isReady else {
            pendingTheme = theme
            return
        }
        JavascriptFunction("window.setTheme('\(theme.rawValue)')").evaluate(in: webView)
    }

    // MARK: - Read Only

    public func setReadOnly(_ readOnly: Bool) {
        guard isReady else { return }
        JavascriptFunction("window.setReadOnly(\(readOnly))").evaluate(in: webView)
    }

    // MARK: - Focus

    public func focus() {
        guard isReady else { return }
        JavascriptFunction("window.focusEditor()").evaluate(in: webView)
    }

    // MARK: - Helpers

    private func escapeForJS(_ string: String) -> String {
        let data = try! JSONEncoder().encode(string)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    private func applyPendingState() {
        if let content = pendingContent {
            setContent(content)
            pendingContent = nil
        }
        if let language = pendingLanguage {
            setLanguage(language)
            pendingLanguage = nil
        }
        if let theme = pendingTheme {
            setTheme(theme)
            pendingTheme = nil
        } else {
            setTheme(.default)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension CodeMirrorVM: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "editorReady":
            isReady = true
            applyPendingState()

        case "contentChanged":
            isDirty = true
            if let content = message.body as? String {
                onContentChange?(content)
            }

        default:
            break
        }
    }
}

import SlideDatabase
import SwiftUI
import Sharing

/// Renders a single object's content based on its type.
/// Extracted from ObjectContentView to support multi-panel layouts.
struct TabContentView: View {
    let object: TaskObject
    let registry: WebViewRegistry
    let terminalRegistry: TerminalRegistry
    let codeEditorRegistry: CodeEditorRegistry
    let onMetadataUpdate: (TaskObject) -> Void
    var projectId: UUID? = nil
    var projectName: String? = nil
    @Shared(.appStorage("isDarkMode")) var isDarkMode = false

    var body: some View {
        switch object.objectType {
        case .link:
            if let url = object.url {
                let webView = registry.ensureWebView(
                    objectId: object.uuidValue,
                    initialURL: url,
                    onMetadata: handleMetadata
                )
                WebViewHost(webView: webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyContentView()
            }
        case .note:
            NoteView(object: object, isDarkMode: isDarkMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .pdf:
            PDFContentView(object: object)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .image:
            ImageView(object: object)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .video:
            VideoView(object: object)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .audio:
            AudioView(object: object)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .terminal:
            TerminalContentView(
                object: object,
                terminalRegistry: terminalRegistry,
                projectId: projectId,
                projectName: projectName
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .codeEditor:
            CodeEditorContentView(
                object: object,
                codeEditorRegistry: codeEditorRegistry,
                onContentUpdate: onMetadataUpdate
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .group:
            // Legacy group objects — show as empty
            EmptyContentView()
        }
    }

    private func handleMetadata(objectId: UUID, title: String?, currentURL: URL?, favicon: String?) {
        guard let obj = (object.uuidValue == objectId ? object : nil) else { return }
        var updated = obj
        // Only auto-update title if user hasn't set a custom name
        if let t = title, obj.customName.isEmpty { updated.title = t }
        if let u = currentURL {
            let previousHost = updated.url?.host
            updated.url = u
            let newHost = u.host
            if previousHost != nil, previousHost != newHost, (favicon == nil || favicon?.isEmpty == true) {
                if let fallback = buildFaviconFallback(for: u) {
                    updated.favicon = fallback
                }
            }
        }
        if let f = favicon, !f.isEmpty { updated.favicon = f }
        onMetadataUpdate(updated)
    }

    private func buildFaviconFallback(for pageURL: URL?) -> String? {
        guard let pageURL = pageURL, let host = pageURL.host else { return nil }
        let s2 = "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
        if let url = URL(string: s2) { return url.absoluteString }
        var comps = URLComponents()
        comps.scheme = pageURL.scheme
        comps.host = host
        comps.path = "/favicon.ico"
        return comps.url?.absoluteString
    }
}

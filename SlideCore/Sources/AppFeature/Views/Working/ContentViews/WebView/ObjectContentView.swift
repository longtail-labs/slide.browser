import SlideDatabase
import SwiftUI
import Sharing

public struct ObjectContentView: View {
    let objects: [TaskObject]
    let selectedId: UUID?
    let onMetadataUpdate: (TaskObject) -> Void
    @Shared(.appStorage("isDarkMode")) var isDarkMode = false

    @State private var registry = WebViewRegistry()  // Using @State with @Observable
    @State private var terminalRegistry = TerminalRegistry()
    @State private var isActive = true

    private var selectedObject: TaskObject? {
        guard let id = selectedId else { return nil }
        return objects.first(where: { $0.uuidValue == id })
    }

    // Prewarm all link tabs when object count is small to make switching instant.
    // For larger workspaces, lazily create only opened tabs and keep them alive.
    private let warmUpThreshold = 8

    public var body: some View {
        ZStack {
            // Only mount the active webview to avoid cursor conflicts
            if let selected = selectedObject {
                switch selected.objectType {
                case .link:
                    if let url = selected.url {
                        let webView = registry.ensureWebView(
                            objectId: selected.uuidValue,
                            initialURL: url,
                            onMetadata: handleMetadata
                        )
                        WebViewHost(webView: webView)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .zIndex(1)
                    } else {
                        EmptyContentView()
                            .zIndex(1)
                    }
                case .note:
                    NoteView(object: selected, isDarkMode: isDarkMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(1)
                case .pdf:
                    PDFContentView(object: selected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(1)
                case .image:
                    ImageView(object: selected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(1)
                case .video:
                    VideoView(object: selected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(1)
                case .audio:
                    AudioView(object: selected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(1)
                case .terminal:
                    TerminalContentView(object: selected, terminalRegistry: terminalRegistry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(1)
                case .codeEditor:
                    EmptyContentView()
                        .zIndex(1)
                case .group:
                    EmptyContentView()
                        .zIndex(1)
                }
            } else {
                EmptyContentView()
                    .zIndex(1)
            }
        }
        .onChange(of: objects) { _, newObjects in
            let liveIds = Set(newObjects.map { $0.uuidValue })
            // Prune entries that are no longer in the workspace
            registry.sync(with: liveIds)
            terminalRegistry.sync(with: liveIds)
            // If small, prewarm all link tabs
            if newObjects.count <= warmUpThreshold {
                for object in newObjects where object.objectType == .link {
                    if let url = object.url {
                        _ = registry.ensureWebView(objectId: object.uuidValue, initialURL: url, onMetadata: handleMetadata)
                    }
                }
            }
        }
        .onDisappear {
            print("[ObjectContentView] onDisappear - marking inactive and clearing all WebViews")
            // Mark as inactive to prevent callbacks
            isActive = false
            // Clean up all WebViews and terminals when the workspace is closed
            registry.clearAll()
            terminalRegistry.clearAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("KillAllWebViews"))) { _ in
            print("[ObjectContentView] Received KillAllWebViews notification - marking inactive")
            // Mark as inactive first to prevent any further callbacks
            isActive = false
            // Alternative cleanup trigger from workspace
            registry.clearAll()
            terminalRegistry.clearAll()
        }
    }

    private func handleMetadata(objectId: UUID, title: String?, currentURL: URL?, favicon: String?) {
        // Only process metadata if the view is still active
        guard isActive else { 
            print("[ObjectContentView] Ignoring metadata update - view is not active")
            return 
        }
        guard let object = objects.first(where: { $0.uuidValue == objectId }) else { return }
        var updated = object
        if let t = title { updated.title = t }
        if let u = currentURL {
            let previousHost = updated.url?.host
            updated.url = u
            let newHost = u.host
            // If host changed and we didn't get an explicit favicon yet, set a quick fallback
            if previousHost != nil, previousHost != newHost, (favicon == nil || favicon?.isEmpty == true) {
                if let fallback = buildFaviconFallback(for: u) {
                    #if DEBUG
                    print("[ObjectContentView] Host changed (\(previousHost ?? "nil") -> \(newHost ?? "nil")); setting fallback favicon: \(fallback)")
                    #endif
                    updated.favicon = fallback
                }
            }
        }
        if let f = favicon, !f.isEmpty { updated.favicon = f }
        onMetadataUpdate(updated)
    }

    // Minimal favicon fallback, mirrors logic in WebView + TabButton
    private func buildFaviconFallback(for pageURL: URL?) -> String? {
        guard let pageURL = pageURL, let host = pageURL.host else { return nil }
        // Primary: Google s2
        let s2 = "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
        if let url = URL(string: s2) { return url.absoluteString }
        // Fallback: origin /favicon.ico
        var comps = URLComponents()
        comps.scheme = pageURL.scheme
        comps.host = host
        comps.path = "/favicon.ico"
        return comps.url?.absoluteString
    }
}

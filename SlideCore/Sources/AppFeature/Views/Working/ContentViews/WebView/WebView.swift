import SwiftUI
import WebKit
import AppKit
// Toggle verbose WebView navigation logging while in DEBUG builds
#if DEBUG
@inline(__always) private func webLog(_ message: @autoclosure () -> String) {
    // Set to true temporarily when you need deep WebKit traces
    let WEBVIEW_VERBOSE_LOGS = false
    if WEBVIEW_VERBOSE_LOGS { print(message()) }
}
#endif

// MARK: - Custom context menu support (macOS)
@available(macOS 11.0, *)
final class ContextMenuWebView: WKWebView {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    enum ContextualMenuAction {
        case summarizeTarget
    }

    // Set when a custom hijacked item is chosen; cleared shortly after menu closes
    var contextualMenuAction: ContextualMenuAction?

    weak var actionHandler: WebContextActionHandling?
    // Bridge download hijack
    @objc private func downloadImageFromContextMenu() {
        let js = """
        (function(){
          try {
            const info = (window.__slideCtx||{});
            return info.imageURL || null;
          } catch(e) { return null }
        })();
        """
        self.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            guard let controller = (self.navigationDelegate as? WebTabController) else { return }
            guard let s = result as? String, let url = URL(string: s) else {
                NSSound.beep()
                return
            }
            controller.startNativeDownload(from: url)
        }
    }

    // Insert custom items while keeping system items like copy/paste intact
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        var items = menu.items
        
        // Remove any existing "Search with Google" items that WebKit provides
        var indicesToRemove: [Int] = []
        for (idx, item) in items.enumerated().reversed() {
            let title = item.title.lowercased()
            // Check for search-related items by title
            if title.contains("search") && (title.contains("google") || title.contains("web")) {
                indicesToRemove.append(idx)
            } else if let itemId = item.identifier?.rawValue {
                // Also check by WebKit identifier
                if itemId.contains("Search") || itemId == "WKMenuItemIdentifierSearchWeb" {
                    indicesToRemove.append(idx)
                }
            }
        }
        
        // Remove the built-in search items
        for idx in indicesToRemove.sorted(by: >) {
            items.remove(at: idx)
        }
        
        // Add our custom Save to Note action
        let saveToNoteItem = NSMenuItem(title: "Save Selection to Note", action: #selector(saveSelectionToNote), keyEquivalent: "")
        saveToNoteItem.target = self
        
        // Add our custom Search with Google
        let searchWithGoogleItem = NSMenuItem(title: "Search with Google", action: #selector(searchWithGoogle), keyEquivalent: "")
        searchWithGoogleItem.target = self
        
        // Place our custom items after first separator if one exists
        if let firstSeparatorIndex = items.firstIndex(where: { $0.isSeparatorItem }) {
            items.insert(searchWithGoogleItem, at: firstSeparatorIndex + 1)
            items.insert(saveToNoteItem, at: firstSeparatorIndex + 1)
        } else {
            items.insert(searchWithGoogleItem, at: 0)
            items.insert(saveToNoteItem, at: 0)
        }

        // For link/image/media, add a custom "Summarize …" that hijacks the default action
        // Commented out for now
        /* for idx in (0..<items.count).reversed() {
            guard let id = items[idx].identifier?.rawValue else { continue }
            if id == "WKMenuItemIdentifierOpenLinkInNewWindow" ||
               id == "WKMenuItemIdentifierOpenImageInNewWindow" ||
               id == "WKMenuItemIdentifierOpenMediaInNewWindow" ||
               id == "WKMenuItemIdentifierOpenFrameInNewWindow" {

                let objectLabel: String
                switch id {
                case "WKMenuItemIdentifierOpenLinkInNewWindow": objectLabel = "Link"
                case "WKMenuItemIdentifierOpenImageInNewWindow": objectLabel = "Image"
                case "WKMenuItemIdentifierOpenMediaInNewWindow": objectLabel = "Media"
                default: objectLabel = "Frame"
                }

                let action = #selector(processMenuItem(_:))
                let summarizeItem = NSMenuItem(title: "Summarize \(objectLabel)…", action: action, keyEquivalent: "")
                summarizeItem.identifier = NSUserInterfaceItemIdentifier("summarizeTarget")
                summarizeItem.target = self
                summarizeItem.representedObject = items[idx] // original item to forward action
                items.insert(summarizeItem, at: idx + 1)
            }
        } */
        
        for idx in (0..<items.count).reversed() {
            let item = items[idx]
            let id = item.identifier?.rawValue ?? ""
            let title = item.title.lowercased()
            // Hijack system "Download Image" to ensure it saves via Slide
            let downloadImageIDs: Set<String> = [
                "WKMenuItemIdentifierDownloadImage",
                "WKMenuItemIdentifierDownloadImageToDisk",
                "WKMenuItemIdentifierSaveImageToDownloads"
            ]
            // Also hijack media and linked-file downloads
            let downloadMediaIDs: Set<String> = [
                "WKMenuItemIdentifierDownloadMedia",
                "WKMenuItemIdentifierDownloadMediaToDisk",
                "WKMenuItemIdentifierSaveVideoToDownloads",
                "WKMenuItemIdentifierSaveAudioToDownloads"
            ]
            let downloadLinkedIDs: Set<String> = [
                "WKMenuItemIdentifierDownloadLinkedFile",
                "WKMenuItemIdentifierDownloadLinkedFileToDisk"
            ]

            if downloadImageIDs.contains(id) {
                item.target = self
                item.action = #selector(downloadImageFromContextMenu)
                #if DEBUG
                print("🧰 [ContextMenuWebView] Hijacked 'Download Image' menu item → native download")
                #endif
            } else if downloadMediaIDs.contains(id) || (title.contains("download") && (title.contains("video") || title.contains("audio"))) {
                item.target = self
                item.action = #selector(downloadMediaFromContextMenu)
                #if DEBUG
                print("🧰 [ContextMenuWebView] Hijacked 'Download Media' menu item → native download")
                #endif
            } else if downloadLinkedIDs.contains(id) || (title.contains("download") && title.contains("linked")) {
                item.target = self
                item.action = #selector(downloadLinkedFromContextMenu)
                #if DEBUG
                print("🧰 [ContextMenuWebView] Hijacked 'Download Linked File' menu item → native download")
                #endif
            }
        }

        menu.items = items
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        // Clear after a short delay; actions are processed asynchronously
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.contextualMenuAction = nil
        }
    }

    // Bridge download hijack for media (video/audio)
    @objc private func downloadMediaFromContextMenu() {
        #if DEBUG
        print("🎯 [ContextMenuWebView] downloadMediaFromContextMenu invoked")
        #endif
        let js = """
        (function(){
          try {
            const info = (window.__slideCtx||{});
            return info.mediaURL || info.linkURL || null;
          } catch(e) { return null }
        })();
        """
        self.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            guard let controller = (self.navigationDelegate as? WebTabController) else { return }
            guard let s = result as? String, let url = URL(string: s) else {
                #if DEBUG
                print("⚠️ [ContextMenuWebView] No media URL resolved from context menu")
                #endif
                NSSound.beep()
                return
            }
            #if DEBUG
            print("⬇️ [ContextMenuWebView] Starting native media download from \(url.absoluteString)")
            #endif
            controller.startNativeDownload(from: url)
        }
    }

    // Bridge download hijack for generic linked file
    @objc private func downloadLinkedFromContextMenu() {
        #if DEBUG
        print("🎯 [ContextMenuWebView] downloadLinkedFromContextMenu invoked")
        #endif
        let js = """
        (function(){
          try {
            const info = (window.__slideCtx||{});
            return info.linkURL || info.mediaURL || info.imageURL || null;
          } catch(e) { return null }
        })();
        """
        self.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            guard let controller = (self.navigationDelegate as? WebTabController) else { return }
            guard let s = result as? String, let url = URL(string: s) else {
                #if DEBUG
                print("⚠️ [ContextMenuWebView] No link URL resolved from context menu")
                #endif
                NSSound.beep()
                return
            }
            #if DEBUG
            print("⬇️ [ContextMenuWebView] Starting native linked-file download from \(url.absoluteString)")
            #endif
            controller.startNativeDownload(from: url)
        }
    }

    // MARK: - Page-level actions
    @objc private func summarizePage() {
        guard let url = self.url else { return }
        actionHandler?.summarize(url: url)
    }

    @objc private func explainSelection() {
        let js = "window.getSelection().toString();"
        self.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            self.actionHandler?.summarizeSelection(text: text)
        }
    }
    
    @objc private func saveSelectionToNote() {
        let js = "window.getSelection().toString();"
        self.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            self.actionHandler?.saveSelectionToNote(text: text, url: self.url)
        }
    }
    
    @objc private func searchWithGoogle() {
        let js = "window.getSelection().toString();"
        self.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            self.actionHandler?.searchWithGoogle(text: text)
        }
    }

    // MARK: - Hijacked item processing
    @objc func processMenuItem(_ menuItem: NSMenuItem) {
        self.contextualMenuAction = nil
        if let original = menuItem.representedObject as? NSMenuItem {
            if menuItem.identifier?.rawValue == "summarizeTarget" {
                self.contextualMenuAction = .summarizeTarget
            }
            if let action = original.action {
                original.target?.perform(action, with: original)
            }
        }
    }
}

// MARK: - Actions protocol the controller implements
protocol WebContextActionHandling: AnyObject {
    func summarize(url: URL)
    func summarizeSelection(text: String)
    func saveSelectionToNote(text: String, url: URL?)
    func searchWithGoogle(text: String)
}

// MARK: - Find Notifications
extension Notification.Name {
    static let webFindNext = Notification.Name("WebViewFindNext")
    static let webFindPrevious = Notification.Name("WebViewFindPrevious")
    static let webGoBack = Notification.Name("WebViewGoBack")
    static let webGoForward = Notification.Name("WebViewGoForward")
    static let webReload = Notification.Name("WebViewReload")
    static let webZoomIn = Notification.Name("WebViewZoomIn")
    static let webZoomOut = Notification.Name("WebViewZoomOut")
    static let webResetZoom = Notification.Name("WebViewResetZoom")
    static let webNavigateToURL = Notification.Name("WebViewNavigateToURL")
    // AI actions emitted by custom context menu
    static let webAISummarizeURL = Notification.Name("WebViewAISummarizeURL")
    static let webAISummarizeSelection = Notification.Name("WebViewAISummarizeSelection")
    // Save to note action
    static let webSaveSelectionToNote = Notification.Name("WebViewSaveSelectionToNote")
    // Search with Google action
    static let webSearchWithGoogle = Notification.Name("WebViewSearchWithGoogle")
    // Open link in new tab (Cmd+Click)
    static let webOpenLinkInNewTab = Notification.Name("WebViewOpenLinkInNewTab")
    static let webProgressUpdated = Notification.Name("WebViewProgressUpdated")
    // Download events
    static let webDownloadStarted = Notification.Name("WebViewDownloadStarted")
    static let webDownloadProgress = Notification.Name("WebViewDownloadProgress")
    static let webDownloadFinished = Notification.Name("WebViewDownloadFinished")
}

enum WebFindKeys {
    static let query = "query"
    static let objectId = "objectId"
}

// MARK: - Host that re-parents a given WKWebView
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.focusRingType = .none
        attach(webView, to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if webView.superview !== nsView {
            // Remove any previously hosted views to avoid stacking/constraints conflicts
            nsView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
            // Detach from any previous container and re-parent here
            webView.removeFromSuperviewWithoutNeedingDisplay()
            attach(webView, to: nsView)
        }
    }

    private func attach(_ webView: WKWebView, to container: NSView) {
        webView.focusRingType = .none
        container.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

// MARK: - Per-tab controller holding delegates and observers
@MainActor
final class WebTabController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, WebContextActionHandling {
    let objectId: UUID
    private weak var webView: WKWebView?
    private var observers: [NSObjectProtocol] = []
    private var kvo: [NSKeyValueObservation] = []
    private var currentMagnification: CGFloat = 1.0
    private var popupWindows: [WKWebView: NSWindow] = [:]
    private let onMetadata: (UUID, String?, URL?, String?) -> Void
    private var bridgedControllers = Set<ObjectIdentifier>()
    // Track download destinations by identity
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    // Correlate navigation logs per controller
    private var navSeq: Int = 0
    // Flag to prevent callbacks after cleanup
    private var isCleanedUp = false

    init(objectId: UUID, onMetadata: @escaping (UUID, String?, URL?, String?) -> Void) {
        self.objectId = objectId
        self.onMetadata = onMetadata
        super.init()
        setupObservers()
    }

    // Trigger a JS-side fetch of a blob: URL and pipe it back via blobDownload bridge
    private func downloadBlobURL(_ url: URL) {
        guard let webView = webView else { return }
        let urlString = url.absoluteString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let js = """
        (function(){
          try {
            var href = "\(urlString)";
            fetch(href).then(function(res){ return res.blob(); }).then(function(blob){
              var reader = new FileReader();
              reader.onloadend = function(){
                try {
                  var dataURL = reader.result || '';
                  var base64 = (dataURL && String(dataURL).split(',')[1]) || null;
                  window.webkit.messageHandlers.blobDownload.postMessage({
                    data: base64,
                    mime: blob.type || 'application/octet-stream',
                    filename: 'download'
                  });
                } catch(_) {}
              };
              reader.readAsDataURL(blob);
            });
          } catch(_) {}
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        // Add console log handler (DEBUG only to avoid perf overhead in release)
        #if DEBUG
        webView.configuration.userContentController.add(self, name: "consoleLog")
        #endif
        
        installInPageNavigationBridge(on: webView)
        observeProgress(on: webView)
        observeTitleAndURL(on: webView)
    }

    private func setupObservers() {
        let nextObs = NotificationCenter.default.addObserver(forName: .webFindNext, object: nil, queue: .main) { [weak self] note in
            self?.handleFind(note: note, backwards: false)
        }
        let prevObs = NotificationCenter.default.addObserver(forName: .webFindPrevious, object: nil, queue: .main) { [weak self] note in
            self?.handleFind(note: note, backwards: true)
        }
        let backObs = NotificationCenter.default.addObserver(forName: .webGoBack, object: nil, queue: .main) { [weak self] note in
            self?.handleNav(note: note, action: .back)
        }
        let fwdObs = NotificationCenter.default.addObserver(forName: .webGoForward, object: nil, queue: .main) { [weak self] note in
            self?.handleNav(note: note, action: .forward)
        }
        let reloadObs = NotificationCenter.default.addObserver(forName: .webReload, object: nil, queue: .main) { [weak self] note in
            self?.handleNav(note: note, action: .reload)
        }
        let zoomInObs = NotificationCenter.default.addObserver(forName: .webZoomIn, object: nil, queue: .main) { [weak self] note in
            self?.handleZoom(note: note, op: .in)
        }
        let zoomOutObs = NotificationCenter.default.addObserver(forName: .webZoomOut, object: nil, queue: .main) { [weak self] note in
            self?.handleZoom(note: note, op: .out)
        }
        let zoomResetObs = NotificationCenter.default.addObserver(forName: .webResetZoom, object: nil, queue: .main) { [weak self] note in
            self?.handleZoom(note: note, op: .reset)
        }
        let navigateObs = NotificationCenter.default.addObserver(forName: .webNavigateToURL, object: nil, queue: .main) { [weak self] note in
            self?.handleNavigateToURL(note: note)
        }
        let saveSelectionObs = NotificationCenter.default.addObserver(forName: Notification.Name("TriggerSaveSelection"), object: nil, queue: .main) { [weak self] note in
            self?.handleTriggerSaveSelection(note: note)
        }
        observers.append(contentsOf: [nextObs, prevObs, backObs, fwdObs, reloadObs, zoomInObs, zoomOutObs, zoomResetObs, navigateObs, saveSelectionObs])
    }

    deinit {
        // Ensure we never leave stray popup windows around.
        // deinit is nonisolated; schedule UI cleanup on the main actor.
        let id = objectId
        let popupsSnapshot = popupWindows
        if !popupsSnapshot.isEmpty {
            Task { @MainActor in
                print("🧹 [WebTabController] Closing \(popupsSnapshot.count) popup window(s) for object=\(id.uuidString.prefix(8)))")
                for (popupWebView, window) in popupsSnapshot {
                    window.close()
                    popupWebView.navigationDelegate = nil
                    popupWebView.uiDelegate = nil
                    popupWebView.removeFromSuperview()
                }
            }
        }
        // Explicitly invalidate KVO observations to release promptly
        kvo.forEach { $0.invalidate() }
        kvo.removeAll()
        isCleanedUp = true
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
    
    func markAsCleanedUp() {
        isCleanedUp = true
    }

    // Explicitly close and remove any popup NSWindows this controller created
    func closeAllPopups() {
        guard !popupWindows.isEmpty else { return }
        print("🧹 [WebTabController] Closing \(popupWindows.count) popup window(s) for object=\(objectId.uuidString.prefix(8))")
        for (popupWebView, window) in popupWindows {
            window.close()
            popupWebView.navigationDelegate = nil
            popupWebView.uiDelegate = nil
            popupWebView.removeFromSuperview()
        }
        popupWindows.removeAll()
    }

    // MARK: - Navigation handlers
    private func handleFind(note: Notification, backwards: Bool) {
        guard let noteObjectId = note.userInfo?[WebFindKeys.objectId] as? UUID,
              noteObjectId == objectId,
              let query = note.userInfo?[WebFindKeys.query] as? String,
              !query.isEmpty,
              let webView = webView else { return }

        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        webView.find(query, configuration: config) { _ in }
    }

    private enum NavAction { case back, forward, reload }
    private func handleNav(note: Notification, action: NavAction) {
        guard let noteObjectId = note.userInfo?[WebFindKeys.objectId] as? UUID,
              noteObjectId == objectId,
              let webView = webView else { return }

        switch action {
        case .back:
            if webView.canGoBack { webView.goBack() }
        case .forward:
            if webView.canGoForward { webView.goForward() }
        case .reload:
            webView.reload()
        }
    }

    private enum ZoomOp { case `in`, out, reset }
    private func handleZoom(note: Notification, op: ZoomOp) {
        guard let noteObjectId = note.userInfo?[WebFindKeys.objectId] as? UUID,
              noteObjectId == objectId,
              let webView = webView else { return }

        let step: CGFloat = 0.1
        switch op {
        case .in:
            currentMagnification = min(currentMagnification + step, 3.0)
        case .out:
            currentMagnification = max(currentMagnification - step, 0.5)
        case .reset:
            currentMagnification = 1.0
        }
        // Prefer pageZoom for proper page scaling
        webView.pageZoom = currentMagnification
    }
    
    private func handleNavigateToURL(note: Notification) {
        guard let noteObjectId = note.userInfo?[WebFindKeys.objectId] as? UUID,
              noteObjectId == objectId,
              let url = note.userInfo?["url"] as? URL,
              let webView = webView else { return }
        
        // Explicit navigation from user action (e.g., Cmd+L)
        webView.load(URLRequest(url: url))
    }
    
    private func handleTriggerSaveSelection(note: Notification) {
        guard let noteObjectId = note.userInfo?[WebFindKeys.objectId] as? UUID,
              noteObjectId == objectId,
              let webView = webView else { return }
        
        // Get the current selection and save to note
        let js = "window.getSelection().toString();"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            
            // Post notification with the selected text
            NotificationCenter.default.post(name: .webSaveSelectionToNote, object: nil, userInfo: [
                WebFindKeys.objectId: self.objectId,
                "text": text,
                "url": webView.url as Any
            ])
        }
    }

    // MARK: - WKUIDelegate for popups
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        #if DEBUG
        print("🪟 [WebView] createWebViewWith called")
        print("  URL: \(navigationAction.request.url?.absoluteString ?? "nil")")
        print("  Target frame: \(navigationAction.targetFrame?.description ?? "nil")")
        print("  Navigation type: \(navigationAction.navigationType.rawValue)")
        #endif
        
        // Allow true download actions to proceed so we receive didBecome download callbacks
        #if os(macOS)
        if #available(macOS 11.0, *) {
            if navigationAction.shouldPerformDownload {
                #if DEBUG
                print("  → Download action, returning nil")
                #endif
                return nil
            }
        }
        #endif
        
        // If a custom contextual menu action hijacked the default, handle it first
        if let custom = (webView as? ContextMenuWebView)?.contextualMenuAction {
            if let url = navigationAction.request.url {
                switch custom {
                case .summarizeTarget:
                    #if DEBUG
                    print("  → Custom summarize action")
                    #endif
                    self.summarize(url: url)
                }
            }
            return nil
        }
        
        // Determine if this should be a popup or new tab based on window features and context
        let shouldUsePopup: Bool = {
            // If the navigation action has explicit window features (size, position, etc.)
            // or if it's a script-initiated popup (navigation type -1), use a real popup
            if navigationAction.navigationType.rawValue == -1 {
                // Script-initiated (window.open) - likely OAuth or intentional popup
                return true
            }
            
            // If windowFeatures specify dimensions, it's meant to be a popup
            if windowFeatures.width != nil || windowFeatures.height != nil {
                return true
            }
            
            // For everything else (regular links with target="_blank"), open in new tab
            return false
        }()
        
        if !shouldUsePopup, let url = navigationAction.request.url {
            #if DEBUG
            print("  → Opening in new tab: \(url)")
            #endif
            NotificationCenter.default.post(name: .webOpenLinkInNewTab, object: nil, userInfo: [
                WebFindKeys.objectId: objectId,
                "url": url
            ])
            return nil
        }
        
        // Create a real popup window
        #if DEBUG
        print("  → Creating popup window")
        #endif
        
        // Clean up any stale popups first
        for (oldWebView, oldWindow) in popupWindows {
            #if DEBUG
            print("  → Cleaning up old popup: \(ObjectIdentifier(oldWebView))")
            #endif
            oldWindow.close()
            oldWebView.navigationDelegate = nil
            oldWebView.uiDelegate = nil
            oldWebView.removeFromSuperview()
        }
        popupWindows.removeAll()
        
        // IMPORTANT: We MUST use the configuration passed to us by WebKit
        // Creating a new configuration causes a crash
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self
        
        // Don't install the in-page navigation bridge on popups - it can interfere with OAuth flows
        // installInPageNavigationBridge(on: popupWebView)

        let minSize = NSSize(width: 480, height: 640)
        let width = max(NSNumber(value: windowFeatures.width?.doubleValue ?? 0).doubleValue, Double(minSize.width))
        let height = max(NSNumber(value: windowFeatures.height?.doubleValue ?? 0).doubleValue, Double(minSize.height))
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable]
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = popupWebView
        window.title = "Sign In"  // Better than blank title
        window.center()
        window.makeKeyAndOrderFront(nil)

        popupWindows[popupWebView] = window
        #if DEBUG
        print("  → Registered popup webView: \(ObjectIdentifier(popupWebView))")
        print("  → Total popups: \(popupWindows.count)")
        #endif
        
        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        #if DEBUG
        print("🪟 [WebView] webViewDidClose called for: \(ObjectIdentifier(webView))")
        #endif
        if let win = popupWindows.removeValue(forKey: webView) {
            win.close()
            #if DEBUG
            print("  → Closed and removed popup window")
            #endif
        }
        
        // Clean up the webView properly
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navSeq &+= 1
        let pendingURL = webView.url?.absoluteString ?? "(about:blank)"
        #if DEBUG
        webLog("🚦 didStartProvisional [#\(navSeq)] url=\(pendingURL)")
        #endif
        NotificationCenter.default.post(name: .webProgressUpdated, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "progress": 0.0
        ])
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        #if DEBUG
        webLog("📡 didCommit [#\(navSeq)] url=\(webView.url?.absoluteString ?? "nil")")
        #endif
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let url = navigationResponse.response.url?.absoluteString ?? "unknown"
        let mimeType = (navigationResponse.response.mimeType ?? "unknown").lowercased()
        let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode
        #if DEBUG
        print("📥 [navResponse] url=\(url) status=\(status.map(String.init) ?? "-") mime=\(mimeType) canShow=\(navigationResponse.canShowMIMEType) main=\(navigationResponse.isForMainFrame)")
        #endif
        
        // Check if this is an OAuth callback that should close the popup
        if let responseURL = navigationResponse.response.url {
            let urlString = responseURL.absoluteString.lowercased()
            // Common OAuth callback patterns that indicate authentication is complete
            let callbackPatterns = [
                "close_popup",
                "auth/callback",
                "oauth/callback", 
                "oauth2callback",
                "googlepopupcallback",
                "auth_success",
                "login_success",
                "signin-success",
                "login-success"
            ]
            
            // Also check for OAuth success with codes/tokens in the URL
            let hasOAuthCode = urlString.contains("code=") || 
                               urlString.contains("token=") || 
                               urlString.contains("access_token=")
            let looksLikeCallback = urlString.contains("callback") || 
                                    urlString.contains("/redirect") || 
                                    urlString.contains("success")
            
            if callbackPatterns.contains(where: { urlString.contains($0) }) || (hasOAuthCode && looksLikeCallback) {
        #if DEBUG
        webLog("🔐 OAuth success detected in popup: \(responseURL)")
        #endif
                // If this is a popup window, check if the page wants to close itself
                if popupWindows.keys.contains(webView) {
                    #if DEBUG
                    webLog("  → Checking if popup wants to close...")
                    #endif
                    // First check if the page has a script to close itself or communicate back
                    let checkScript = """
                    (function() {
                        // Check if page has window.opener and is trying to communicate
                        if (window.opener && !window.opener.closed) {
                            // Some OAuth flows post a message back to opener
                            return 'has_opener';
                        }
                        // Check if page is trying to close itself
                        if (document.body && document.body.innerText && 
                            (document.body.innerText.includes('successfully') || 
                             document.body.innerText.includes('Success') ||
                             document.body.innerText.includes('close this window'))) {
                            return 'should_close';
                        }
                        return 'keep_open';
                    })()
                    """
                    
                    webView.evaluateJavaScript(checkScript) { [weak self] result, _ in
                        if let status = result as? String {
                            #if DEBUG
                            webLog("  → Popup status: \(status)")
                            #endif
                            if status == "should_close" {
                                // Tell the popup window to close itself via JavaScript first
                                webView.evaluateJavaScript("window.close()") { _, _ in
                                    // Then clean it up on our side
                                    DispatchQueue.main.async {
                                        self?.webViewDidClose(webView)
                                    }
                                }
                            }
                            // If has_opener, the page might handle closing itself or communicating back
                        }
                    }
                }
            }
        }
        
        // If the server suggests a download (e.g., Content-Disposition: attachment)
        if let http = navigationResponse.response as? HTTPURLResponse {
            if let cd = http.allHeaderFields["Content-Disposition"] as? String,
               cd.lowercased().contains("attachment") {
                #if DEBUG
                print("  → Download due to Content-Disposition: attachment")
                #endif
                decisionHandler(.download)
                return
            }
        }

        // If WebKit can't display the MIME type, prefer to download
        if !navigationResponse.canShowMIMEType {
            #if DEBUG
            print("  → Download due to unsupported MIME type")
            #endif
            decisionHandler(.download)
            return
        }

        // Allow inline display for PDF/audio/video when the server doesn't force download
        // This avoids janky auto-downloads when simply navigating to a PDF or media URL.

        decisionHandler(.allow)
    }

    // A navigation action (e.g., <a download>) can become a download
    @available(macOS 11.0, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        // Announce start of a download (initial event without filename)
        let idStr = String(ObjectIdentifier(download).hashValue)
        #if DEBUG
        webLog("⬇️ navigationAction became download id=\(idStr)")
        #endif
        NotificationCenter.default.post(name: .webDownloadStarted, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "id": idStr
        ])
    }

    // A navigation response (e.g., attachment) can become a download
    @available(macOS 11.0, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        // Announce start of a download (initial event without filename)
        let idStr = String(ObjectIdentifier(download).hashValue)
        #if DEBUG
        webLog("⬇️ navigationResponse became download id=\(idStr)")
        #endif
        NotificationCenter.default.post(name: .webDownloadStarted, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "id": idStr
        ])
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Track if this webView is a popup window
        let isPopupWindow = popupWindows.values.contains { $0.contentView === webView }
        
        let targetIsMain = navigationAction.targetFrame?.isMainFrame ?? false
        let sourceIsMain = navigationAction.sourceFrame.isMainFrame
        let method = navigationAction.request.httpMethod ?? "GET"
        #if DEBUG
        webLog("📍 [decidePolicyFor] Navigation request:")
        webLog("  URL: \(navigationAction.request.url?.absoluteString ?? "nil")")
        webLog("  Method: \(method)  Type: \(navigationAction.navigationType.rawValue)")
        webLog("  Is popup window: \(isPopupWindow)  WebView: \(ObjectIdentifier(webView))")
        webLog("  Source frame main=\(sourceIsMain)  Target frame main=\(targetIsMain)")
        if #available(macOS 11.0, *) { webLog("  shouldPerformDownload=\(navigationAction.shouldPerformDownload)") }
        #endif
        
        // Only block the exact same URL that the popup is navigating to
        // This prevents the main page from also navigating when window.open is called
        if !isPopupWindow && !popupWindows.isEmpty, let url = navigationAction.request.url {
            let urlString = url.absoluteString
            
            // Check if any popup is currently navigating to this same URL
            for (popupWebView, _) in popupWindows {
                if let popupURL = popupWebView.url?.absoluteString, popupURL == urlString {
                    #if DEBUG
                    webLog("  → BLOCKING duplicate navigation in main window (popup handling this URL)")
                    #endif
                    decisionHandler(.cancel)
                    return
                }
            }
        }
        
        // Intercept blob:/data: links and convert them to native downloads
        if let url = navigationAction.request.url {
            if url.scheme == "data" {
                startNativeDownload(from: url)
                decisionHandler(.cancel)
                return
            } else if url.scheme == "blob" {
                downloadBlobURL(url)
                decisionHandler(.cancel)
                return
            }
        }

        #if os(macOS)
        if #available(macOS 11.0, *) {
            // If this action is intended to download (e.g., <a download>), instruct WebKit to perform a download
            // so we receive the WKDownload callbacks and can show progress UI.
            if navigationAction.shouldPerformDownload {
                #if DEBUG
                webLog("  → Converting navigationAction to download (shouldPerformDownload=true)")
                #endif
                decisionHandler(.download)
                return
            }
        }
        #endif

        // REMOVED: Auto-download for image URLs
        // Images should only be downloaded explicitly via context menu or download links
        // This prevents duplicate downloads when viewing existing image tabs

        // Intercept Command-click or middle-click on links to open in a new tab
        #if os(macOS)
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            if #available(macOS 11.0, *) {
                if navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2 {
                    NotificationCenter.default.post(name: .webOpenLinkInNewTab, object: nil, userInfo: [
                        WebFindKeys.objectId: objectId,
                        "url": url
                    ])
                    decisionHandler(.cancel)
                    return
                }
            }
        }
        #endif

        // target=_blank -> open as new tab (but don't intercept downloads)
        // Note: Our JavaScript removes target="_blank" from POST forms before submission
        // to preserve form data, so we shouldn't see POST requests here anymore
        // BUT: Don't do this for popup windows - they should be allowed to navigate normally
        if !isPopupWindow && navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            #if DEBUG
            print("  → Opening in new tab (target frame is nil)")
            #endif
            // For GET requests, open in new tab as usual
            NotificationCenter.default.post(name: .webOpenLinkInNewTab, object: nil, userInfo: [
                WebFindKeys.objectId: objectId,
                "url": url
            ])
            decisionHandler(.cancel)
            return
        }
        #if DEBUG
        print("  → Allowing navigation")
        #endif
        decisionHandler(.allow)
    }
    
    private func isImageURL(_ url: URL) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "ico", "tiff", "tif"]
        let pathExtension = url.pathExtension.lowercased()
        return imageExtensions.contains(pathExtension)
    }

    // Newer API variant that provides webpage preferences (macOS 11+)
    @available(macOS 11.0, *)
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // Track if this webView is a popup window
        let isPopupWindow = popupWindows.values.contains { $0.contentView === webView }
        
        let targetIsMain = navigationAction.targetFrame?.isMainFrame ?? false
        let sourceIsMain = navigationAction.sourceFrame.isMainFrame
        let method = navigationAction.request.httpMethod ?? "GET"
        #if DEBUG
        print("📍 [decidePolicyFor+Preferences] Navigation request:")
        print("  URL: \(navigationAction.request.url?.absoluteString ?? "nil")")
        print("  Method: \(method)  Type: \(navigationAction.navigationType.rawValue)")
        print("  Is popup window: \(isPopupWindow)  WebView: \(ObjectIdentifier(webView))")
        print("  Source frame main=\(sourceIsMain)  Target frame main=\(targetIsMain)")
        if #available(macOS 11.0, *) {
            print("  shouldPerformDownload=\(navigationAction.shouldPerformDownload)")
        }
        #endif
        
        // Only block the exact same URL that the popup is navigating to
        // This prevents the main page from also navigating when window.open is called
        if !isPopupWindow && !popupWindows.isEmpty, let url = navigationAction.request.url {
            let urlString = url.absoluteString
            
            // Check if any popup is currently navigating to this same URL
            for (popupWebView, _) in popupWindows {
                if let popupURL = popupWebView.url?.absoluteString, popupURL == urlString {
                    #if DEBUG
                    print("  → BLOCKING duplicate navigation in main window (popup handling this URL)")
                    #endif
                    decisionHandler(.cancel, preferences)
                    return
                }
            }
        }
        
        // Intercept blob:/data: links and convert them to native downloads
        if let url = navigationAction.request.url {
            if url.scheme == "data" {
                startNativeDownload(from: url)
                decisionHandler(.cancel, preferences)
                return
            } else if url.scheme == "blob" {
                downloadBlobURL(url)
                decisionHandler(.cancel, preferences)
                return
            }
        }

        // Honor explicit download intents (e.g., context-menu "Download …", <a download>)
        if navigationAction.shouldPerformDownload {
            #if DEBUG
            print("  → Converting navigationAction to download (shouldPerformDownload=true)")
            #endif
            decisionHandler(.download, preferences)
            return
        }

        // REMOVED: Auto-download for image URLs
        // Images should only be downloaded explicitly via context menu or download links
        // This prevents duplicate downloads when viewing existing image tabs

        #if os(macOS)
        // Intercept Command-click or middle-click on links to open in a new tab
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            if navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2 {
                NotificationCenter.default.post(name: .webOpenLinkInNewTab, object: nil, userInfo: [
                    WebFindKeys.objectId: objectId,
                    "url": url
                ])
                decisionHandler(.cancel, preferences)
                return
            }
        }
        #endif

        // target=_blank -> open as new tab (but don't intercept downloads)
        // Note: Our JavaScript removes target="_blank" from POST forms before submission
        // to preserve form data, so we shouldn't see POST requests here anymore
        // BUT: Don't do this for popup windows - they should be allowed to navigate normally
        if !isPopupWindow && navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            #if DEBUG
            print("  → Opening in new tab (target frame is nil)")
            #endif
            // For GET requests, open in new tab as usual
            NotificationCenter.default.post(name: .webOpenLinkInNewTab, object: nil, userInfo: [
                WebFindKeys.objectId: objectId,
                "url": url
            ])
            decisionHandler(.cancel, preferences)
            return
        }
        print("  → Allowing navigation")
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let title = sanitizeTitle(webView.title)
        let currentURL = webView.url
        #if DEBUG
        webLog("✅ didFinish [#\(navSeq)] url=\(currentURL?.absoluteString ?? "nil") title=\(title ?? "")")
        #endif

        // Detect favicon
        let js = """
        (function(){
          function parseSize(s){ if(!s) return 0; let max = 0; s.split(/\\s+/).forEach(p=>{ const parts = p.split('x').map(n=>parseInt(n,10)); if(parts.length===2 && !isNaN(parts[0]) && !isNaN(parts[1])) { max = Math.max(max, Math.max(parts[0], parts[1])); } }); return max; }
          const selectors = ["link[rel~=icon]", "link[rel='icon']", "link[rel='shortcut icon']", "link[rel='apple-touch-icon']", "link[rel='apple-touch-icon-precomposed']", "link[rel='mask-icon']"];
          const links = [];
          selectors.forEach(sel => document.querySelectorAll(sel).forEach(l => links.push(l)));
          if(links.length === 0) return null;
          links.sort((a,b) => (parseSize(b.getAttribute('sizes'))||0) - (parseSize(a.getAttribute('sizes'))||0));
          const href = links[0].href || links[0].getAttribute('href');
          return href || null;
        })()
        """

        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            let detected = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let faviconURL = (detected?.isEmpty == false) ? detected : self.buildFaviconFallback(for: currentURL)
            // Check if still active before sending metadata
            guard !self.isCleanedUp else {
                #if DEBUG
                print("[WebTabController] Ignoring metadata - controller cleaned up")
                #endif
                return
            }
            #if DEBUG
            webLog("🖼 favicon detected=\(detected ?? "nil") fallback=\(faviconURL ?? "nil") host=\(currentURL?.host ?? "nil")")
            #endif
            self.onMetadata(self.objectId, title, currentURL, faviconURL)
        }
        NotificationCenter.default.post(name: .webProgressUpdated, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "progress": 1.0
        ])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Navigation failures are normal for download redirects
        #if DEBUG
        print("⛔️ didFailProvisional error=\(error.localizedDescription)")
        #endif
        NotificationCenter.default.post(name: .webProgressUpdated, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "progress": 1.0
        ])
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Recover from renderer crashes by reloading only if this tab is currently mounted
        // Avoid waking background tabs that are detached from the view hierarchy
        #if DEBUG
        print("💥 webContentProcessDidTerminate — considering reload (mounted=\(webView.superview != nil))")
        #endif
        guard webView.superview != nil, !isCleanedUp else { return }
        webView.reload()
    }

    private func buildFaviconFallback(for pageURL: URL?) -> String? {
        guard let pageURL = pageURL else { return nil }
        guard let host = pageURL.host else {
            return originURL(pageURL, path: "/favicon.ico")?.absoluteString
        }

        let isLikelyPublic = host.contains(".") && host != "localhost"

        if isLikelyPublic {
            return "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
        } else {
            if let localIco = originURL(pageURL, path: "/favicon.ico")?.absoluteString { return localIco }
        }

        if let appleTouch = originURL(pageURL, path: "/apple-touch-icon.png")?.absoluteString { return appleTouch }
        return "https://icons.duckduckgo.com/ip3/\(host).ico"
    }

    // MARK: - WKDownloadDelegate (macOS 11+)
    @available(macOS 11.0, *)
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // Save directly to the user's Downloads directory (no app subfolder)
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destination = uniqueFile(in: downloadsDir, filename: suggestedFilename)
        downloadDestinations[ObjectIdentifier(download)] = destination
        // Include filename for any UI
        let idStr = String(ObjectIdentifier(download).hashValue)
        #if DEBUG
        webLog("📥 download decideDestination id=\(idStr) suggested='\(suggestedFilename)' → \(destination.lastPathComponent)")
        #endif
        NotificationCenter.default.post(name: .webDownloadStarted, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "id": idStr,
            "filename": suggestedFilename
        ])
        completionHandler(destination)
    }

    @available(macOS 11.0, *)
    func download(_ download: WKDownload, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let idStr = String(ObjectIdentifier(download).hashValue)
        let progress: Double = totalBytesExpectedToWrite > 0 ? min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) : 0.0
        NotificationCenter.default.post(name: .webDownloadProgress, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "id": idStr,
            "progress": progress
        ])
    }

    @available(macOS 11.0, *)
    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        if let destination = downloadDestinations[key] {
            // Broadcast to workspace for sidebar ingestion
            #if DEBUG
            webLog("✅ download finished id=\(String(ObjectIdentifier(download).hashValue)) → \(destination.path)")
            #endif
            NotificationCenter.default.post(name: .webDownloadFinished, object: nil, userInfo: [
                WebFindKeys.objectId: objectId,
                "url": destination,
                "id": String(ObjectIdentifier(download).hashValue)
            ])
            downloadDestinations.removeValue(forKey: key)
        } else {
        }
    }

    @available(macOS 11.0, *)
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        #if DEBUG
        webLog("❌ download failed id=\(String(ObjectIdentifier(download).hashValue)) error=\(error.localizedDescription)")
        #endif
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
    }

    private func uniqueFile(in directory: URL, filename: String) -> URL {
        let baseName: String
        let ext: String
        let name = (filename as NSString)
        let proposed = directory.appendingPathComponent(filename)
        if proposed.pathExtension.isEmpty {
            baseName = filename
            ext = ""
        } else {
            baseName = name.deletingPathExtension
            ext = name.pathExtension
        }

        var candidate = proposed
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    // MARK: - File uploads (input type="file")
    #if os(macOS)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }
    #endif

    // MARK: - In-page navigation bridge
    private func observeProgress(on webView: WKWebView) {
        let obs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, change in
            guard let self = self else { return }
            let p = change.newValue ?? webView.estimatedProgress
            NotificationCenter.default.post(name: .webProgressUpdated, object: nil, userInfo: [
                WebFindKeys.objectId: self.objectId,
                "progress": p
            ])
        }
        kvo.append(obs)
    }

    private func installInPageNavigationBridge(on webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        let key = ObjectIdentifier(ucc)
        // Avoid adding duplicate handlers/scripts to the same controller
        guard !bridgedControllers.contains(key) else { return }

        // JavaScript to detect in-page navigations and title/url changes
        let scriptSource = #"""
        (function(){
          function notify(){
            try{window.webkit.messageHandlers.inPageNavigation.postMessage({href: location.href, title: document.title});}catch(e){}
            try{console.log('[InPageNav] href=', location.href, 'title=', document.title);}catch(e){}
          }
          // Observe <title> changes for SPAs that mutate it after load
          try {
            var titleEl = document.querySelector('title');
            if (titleEl) {
              var mo = new MutationObserver(function(){ notify(); });
              mo.observe(titleEl, { subtree: true, childList: true, characterData: true });
            }
          } catch(_){ }
          function wrapHistory(fn){
            const orig = history[fn];
            return function(){
              const ret = orig.apply(this, arguments);
              try{console.log(`[History.${fn}]`, location.href);}catch(e){}
              notify();
              return ret;
            };
          }
          window.addEventListener('hashchange', function(){ console.log('[HashChange]', location.href); notify(); }, true);
          window.addEventListener('popstate', function(){ console.log('[PopState]', location.href); notify(); }, true);
          try { history.pushState = wrapHistory('pushState'); } catch(e) {}
          try { history.replaceState = wrapHistory('replaceState'); } catch(e) {}

          // Framework-specific hooks
          // YouTube Polymer app emits these during navigation
          document.addEventListener('yt-navigate-finish', function(){ try{console.log('[yt-navigate-finish]');}catch(_){ } notify(); }, true);
          document.addEventListener('yt-page-data-updated', function(){ try{console.log('[yt-page-data-updated]');}catch(_){ } notify(); }, true);
          // Turbo / PJAX style hooks (best-effort)
          document.addEventListener('turbo:load', function(){ try{console.log('[turbo:load]');}catch(_){ } notify(); }, true);
          document.addEventListener('pjax:end', function(){ try{console.log('[pjax:end]');}catch(_){ } notify(); }, true);

          // Clicks and form submissions (capture phase)
          document.addEventListener('click', function(e){
            try{
              var a = e.target && e.target.closest ? e.target.closest('a') : null;
              if(a){ console.log('[Click]', a.href, 'target=', a.target || '', 'button=', e.button, 'meta=', !!e.metaKey, 'ctrl=', !!e.ctrlKey); }
              // Intercept downloads initiated via <a download> for blob:/data: URLs
              if (a && a.hasAttribute && a.hasAttribute('download')) {
                var href = a.href || '';
                var filename = a.getAttribute('download') || '';
                if (href.indexOf('blob:') === 0) {
                  e.preventDefault(); e.stopPropagation();
                  try {
                    fetch(href).then(function(res){ return res.blob(); }).then(function(blob){
                      var reader = new FileReader();
                      reader.onloadend = function(){
                        try {
                          var dataURL = reader.result || '';
                          var base64 = (dataURL && String(dataURL).split(',')[1]) || null;
                          window.webkit.messageHandlers.blobDownload.postMessage({
                            data: base64,
                            mime: blob.type || 'application/octet-stream',
                            filename: filename || 'download'
                          });
                        } catch(_) {}
                      };
                      reader.readAsDataURL(blob);
                    });
                  } catch(_) {}
                } else if (href.indexOf('data:') === 0) {
                  e.preventDefault(); e.stopPropagation();
                  try {
                    var comma = href.indexOf(',');
                    var meta = href.substring(5, comma);
                    var base64 = href.substring(comma + 1);
                    if (meta.indexOf(';base64') === -1) { try { base64 = btoa(decodeURIComponent(base64)); } catch(_) {} }
                    var mime = (meta.split(';')[0] || 'application/octet-stream');
                    window.webkit.messageHandlers.blobDownload.postMessage({ data: base64, mime: mime, filename: filename || 'download' });
                  } catch(_) {}
                }
              }
            }catch(_){ }
          }, true);
          document.addEventListener('submit', function(e){
            try{
              var f = e.target; if(f && f.tagName === 'FORM'){
                console.log('[Submit]', (f.method||'GET').toUpperCase(), f.action || location.href, 'target=', f.target||'');
              }
            }catch(_){ }
          }, true);

          // Page lifecycle
          window.addEventListener('beforeunload', function(){ try{console.log('[BeforeUnload]');}catch(_){ } }, true);
          window.addEventListener('pagehide', function(ev){ try{console.log('[PageHide] persisted=', !!ev.persisted);}catch(_){ } });
          window.addEventListener('pageshow', function(ev){ try{console.log('[PageShow] persisted=', !!ev.persisted);}catch(_){ } });
          document.addEventListener('visibilitychange', function(){ try{console.log('[Visibility]', document.visibilityState);}catch(_){ } });

          // Track the last contextmenu target for native integrations (download image, etc.)
          window.__slideCtx = {};
          window.addEventListener('contextmenu', function(ev){
            function findImageURL(el){
              if(!el) return null;
              // direct <img>
              let n = el.closest('img');
              if(n && (n.currentSrc || n.src)) return n.currentSrc || n.src;
              // CSS background-image up the chain
              let e = el;
              while(e){
                try {
                  const bg = getComputedStyle(e).backgroundImage;
                  const m = bg && bg.match(/url\(("|')?(.*?)(\1)\)/);
                  if(m && m[2]) return m[2];
                } catch(_) {}
                e = e.parentElement;
              }
              return null;
            }
            function findMediaURL(el){
              if(!el) return null;
              let m = el.closest ? el.closest('video, audio, source') : null;
              if(!m) return null;
              try {
                if (m.tagName === 'SOURCE' && m.src) return m.src;
                if (m.currentSrc) return m.currentSrc;
                if (m.src) return m.src;
                const s = m.querySelector ? m.querySelector('source') : null;
                if (s && s.src) return s.src;
              } catch(_) {}
              return null;
            }
            function findLinkURL(el){
              if(!el) return null;
              const a = el.closest('a');
              return a ? a.href : null;
            }
            window.__slideCtx = {
              imageURL: findImageURL(ev.target) || null,
              mediaURL: findMediaURL(ev.target) || null,
              linkURL: findLinkURL(ev.target) || null,
              pageURL: location.href
            };
          }, true);
        })();
        """#

        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        ucc.addUserScript(userScript)
        ucc.add(self, name: "inPageNavigation")
        ucc.add(self, name: "blobDownload")
        bridgedControllers.insert(key)
    }

    // Observe KVO for title/url to catch late updates not covered by JS bridge
    private func observeTitleAndURL(on webView: WKWebView) {
        var lastURL: String? = nil
        var lastTitle: String? = nil

        let emit: () -> Void = { [weak self, weak webView] in
            guard let self = self, let webView = webView, !self.isCleanedUp else { return }
            let t = self.sanitizeTitle(webView.title)
            let u = webView.url
            let uString = u?.absoluteString
            if uString != lastURL || t != lastTitle {
                lastURL = uString
                lastTitle = t
                self.onMetadata(self.objectId, t, u, nil)
            }
        }

        let tObs = webView.observe(\.title, options: [.new]) { webView, _ in
            #if DEBUG
            webLog("🔖 KVO title=\(webView.title ?? "")")
            #endif
            emit()
        }
        let uObs = webView.observe(\.url, options: [.new]) { webView, _ in
            #if DEBUG
            webLog("🔗 KVO url=\(webView.url?.absoluteString ?? "nil")")
            #endif
            emit()
        }
        kvo.append(contentsOf: [tObs, uObs])
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "inPageNavigation":
            if let body = message.body as? [String: Any] {
                let href = body["href"] as? String
                let title = sanitizeTitle(body["title"] as? String)
                let url = href.flatMap { URL(string: $0) }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard !self.isCleanedUp else {
                        #if DEBUG
                        print("[WebTabController] Ignoring metadata from JS - controller cleaned up")
                        #endif
                        return
                    }
                    #if DEBUG
                    webLog("🧭 inPageNav → title=\(title ?? "") url=\(url?.absoluteString ?? "nil")")
                    #endif
                    self.onMetadata(self.objectId, title, url, nil)
                }
            } else if let href = message.body as? String {
                let url = URL(string: href)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard !self.isCleanedUp else {
                    #if DEBUG
                    print("[WebTabController] Ignoring metadata from JS href - controller cleaned up")
                    #endif
                        return
                    }
                    #if DEBUG
                    webLog("🧭 inPageNav[href] → url=\(url?.absoluteString ?? "nil")")
                    #endif
                    self.onMetadata(self.objectId, nil, url, nil)
                }
            }
        case "blobDownload":
            // Expected body: { data: base64, mime: string, filename: string }
            if let body = message.body as? [String: Any], let b64 = body["data"] as? String {
                let filename = (body["filename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let suggested = (filename?.isEmpty == false) ? filename! : "download"
                if let data = Data(base64Encoded: b64) {
                    // Save using native path and emit download finished
                    saveDownloadedData(data, suggestedFilename: suggested, downloadId: nil)
                } else {
                    #if DEBUG
                    print("[WebTabController] blobDownload: failed to decode base64 (")
                    #endif
                }
            }
        // case "consoleLog":
			// print("Log from web page: \(message.body)")
            // Console log from web page: \(message.body)
        default:
            break
        }
    }

    // Treat empty/whitespace titles as nil to avoid clearing good titles during SPA transitions
    private func sanitizeTitle(_ title: String?) -> String? {
        guard let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.lowercased() == "undefined" { return nil }
        return t
    }

    private func originURL(_ pageURL: URL, path: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = pageURL.scheme
        comps.host = pageURL.host
        comps.port = pageURL.port
        comps.path = path
        return comps.url
    }

    // MARK: - WebContextActionHandling
    func summarize(url: URL) {
        NotificationCenter.default.post(name: .webAISummarizeURL, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "url": url
        ])
    }

    func summarizeSelection(text: String) {
        NotificationCenter.default.post(name: .webAISummarizeSelection, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "text": text,
            "url": webView?.url as Any
        ])
    }
    
    func saveSelectionToNote(text: String, url: URL?) {
        NotificationCenter.default.post(name: .webSaveSelectionToNote, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "text": text,
            "url": url as Any
        ])
    }
    
    func searchWithGoogle(text: String) {
        NotificationCenter.default.post(name: .webSearchWithGoogle, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "text": text
        ])
    }
}

// MARK: - Native download helper
extension WebTabController {
    func startNativeDownload(from url: URL) {
        // Generate an ID for progress UI
        let downloadId = "native-\(UUID().uuidString)"
        NotificationCenter.default.post(name: .webDownloadStarted, object: nil, userInfo: [
            WebFindKeys.objectId: objectId,
            "id": downloadId,
            "filename": Self.suggestedFilename(from: url) ?? url.lastPathComponent
        ])
        // Handle data URLs inline
        if url.scheme == "data" {
            if let data = Self.dataFromDataURL(url.absoluteString) {
                let filename = Self.suggestedFilename(from: url) ?? "download"
                self.saveDownloadedData(data, suggestedFilename: filename, downloadId: downloadId)
            } else {
            }
            return
        }
        // Use URLSession with delegate for http(s) to report progress
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        class NativeDownloadDelegate: NSObject, URLSessionDownloadDelegate {
            weak var owner: WebTabController?
            let id: String
            let originalURL: URL
            let objectId: UUID
            init(owner: WebTabController, id: String, originalURL: URL, objectId: UUID) { self.owner = owner; self.id = id; self.originalURL = originalURL; self.objectId = objectId }
            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
                let progress: Double = totalBytesExpectedToWrite > 0 ? min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) : 0.0
                NotificationCenter.default.post(name: .webDownloadProgress, object: nil, userInfo: [
                    WebFindKeys.objectId: objectId,
                    "id": id,
                    "progress": progress
                ])
            }
            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
                let filename = downloadTask.response?.suggestedFilename ?? originalURL.lastPathComponent
                do {
                    let data = try Data(contentsOf: location)
                    Task { @MainActor [weak owner] in
                        guard let owner else { return }
                        owner.saveDownloadedData(data, suggestedFilename: filename, downloadId: id)
                    }
                } catch {
                }
            }
        }
        let delegate = NativeDownloadDelegate(owner: self, id: downloadId, originalURL: url, objectId: self.objectId)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        task.resume()
    }

    private func saveDownloadedData(_ data: Data, suggestedFilename: String, downloadId: String?) {
        // Save directly to the user's Downloads directory (no app subfolder)
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destination = uniqueFile(in: downloadsDir, filename: suggestedFilename)
        do {
            try data.write(to: destination)
            DispatchQueue.main.async {
                var info: [String: Any] = [
                    WebFindKeys.objectId: self.objectId,
                    "url": destination
                ]
                if let downloadId { info["id"] = downloadId }
                NotificationCenter.default.post(name: .webDownloadFinished, object: nil, userInfo: info)
            }
        } catch {
        }
    }

    private static func suggestedFilename(from url: URL) -> String? {
        if url.scheme == "data" {
            // Try to derive extension from media type
            if let (mime, _) = Self.parseDataURL(url.absoluteString) {
                let ext: String
                switch mime {
                case let s where s.contains("png"): ext = "png"
                case let s where s.contains("jpeg"): ext = "jpg"
                case let s where s.contains("jpg"): ext = "jpg"
                case let s where s.contains("gif"): ext = "gif"
                case let s where s.contains("webp"): ext = "webp"
                case let s where s.contains("svg"): ext = "svg"
                default: ext = "bin"
                }
                return "image.\(ext)"
            }
        }
        let name = url.lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func dataFromDataURL(_ dataURL: String) -> Data? {
        return Self.parseDataURL(dataURL)?.1
    }

    private static func parseDataURL(_ dataURL: String) -> (String, Data)? {
        // data:[<mediatype>][;base64],<data>
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let meta = dataURL[..<comma]
        let dataPart = dataURL[dataURL.index(after: comma)...]
        let isBase64 = meta.contains(";base64")
        let mime: String = {
            let s = String(meta)
            if let range = s.range(of: ":") { return String(s[s.index(after: range.lowerBound)...]) }
            return "application/octet-stream"
        }()
        let data: Data?
        if isBase64 {
            data = Data(base64Encoded: String(dataPart))
        } else {
            data = String(dataPart).removingPercentEncoding?.data(using: .utf8)
        }
        guard let d = data else { return nil }
        return (mime, d)
    }
}

// MARK: - Registry keeping persistent WKWebViews per object
@MainActor
@Observable final class WebViewRegistry {
    static let sharedProcessPool = WKProcessPool()
    private struct Entry {
        let webView: WKWebView
        let controller: WebTabController
    }

    private var entries: [UUID: Entry] = [:]

    func ensureWebView(
        objectId: UUID,
        initialURL: URL,
        onMetadata: @escaping (UUID, String?, URL?, String?) -> Void
    ) -> WKWebView {
        if let entry = entries[objectId] {
            // Do NOT force reloads for existing webviews based on model URL.
            // The webview already owns navigation (SPA pushState, etc.).
            return entry.webView
        }

        let config = WKWebViewConfiguration()
        // Render progressively; avoid visual jank on large pages
        config.suppressesIncrementalRendering = false
        // Share cookies/session across all webviews
        config.processPool = WebViewRegistry.sharedProcessPool
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 10.15, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        // Prefer desktop layout explicitly to avoid mobile-style rendering on some sites
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        
        // Add script to intercept form submissions with target="_blank"
        // This ensures POST data is preserved when forms are submitted
        let formScript = """
        (function() {
            // Function to process forms and remove target="_blank"
            function processForms() {
                var forms = document.getElementsByTagName('form');
                for (var i = 0; i < forms.length; i++) {
                    if (forms[i].target === '_blank' && (forms[i].method || 'GET').toUpperCase() === 'POST') {
                        console.log('[FormIntercept] Removing target=_blank from POST form:', forms[i].action);
                        forms[i].removeAttribute('target');
                        // Also set target to _self explicitly
                        forms[i].target = '_self';
                    }
                }
            }
            
            // Process forms when DOM is ready
            function init() {
                processForms();
                
                // Watch for dynamically added forms
                var observer = new MutationObserver(function(mutations) {
                    var needsProcessing = false;
                    mutations.forEach(function(mutation) {
                        mutation.addedNodes.forEach(function(node) {
                            if (node.tagName === 'FORM' || (node.querySelectorAll && node.querySelectorAll('form').length > 0)) {
                                needsProcessing = true;
                            }
                        });
                    });
                    if (needsProcessing) {
                        processForms();
                    }
                });
                observer.observe(document.body, { childList: true, subtree: true });
                
                // Also intercept form submission as a backup
                document.addEventListener('submit', function(e) {
                    var form = e.target;
                    if (form && form.tagName === 'FORM' && form.target === '_blank' && (form.method || 'GET').toUpperCase() === 'POST') {
                        console.log('[FormIntercept] Last-chance removal of target=_blank on submit');
                        form.removeAttribute('target');
                        form.target = '_self';
                    }
                }, true);
            }
            
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', init);
            } else {
                // DOM is already ready
                init();
            }
        })();
        """
        let formUserScript = WKUserScript(source: formScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(formUserScript)
        
        // Add console logging bridge and window.open interceptor (DEBUG only)
        #if DEBUG
        let consoleScript = """
        (function() {
            var originalLog = console.log;
            console.log = function() {
                originalLog.apply(console, arguments);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleLog) {
                    window.webkit.messageHandlers.consoleLog.postMessage(
                        Array.from(arguments).map(String).join(' ')
                    );
                }
            };
            
            // Intercept window.open to log popup attempts
            var originalOpen = window.open;
            window.open = function(url, target, features) {
                console.log('[Slide] window.open called with:', url, target, features);
                var result = originalOpen.call(window, url, target, features);
                if (!result) {
                    console.log('[Slide] window.open BLOCKED - popup was prevented');
                } else {
                    console.log('[Slide] window.open SUCCESS - popup created');
                }
                return result;
            };
        })();
        """
        let consoleUserScript = WKUserScript(source: consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(consoleUserScript)
        #endif
        let webView: WKWebView
        if #available(macOS 11.0, *) {
            let cmw = ContextMenuWebView(frame: .zero, configuration: config)
            webView = cmw
        } else {
            webView = WKWebView(frame: .zero, configuration: config)
        }
        webView.setValue(false, forKey: "drawsBackground")
        webView.pageZoom = 1.0
        webView.allowsBackForwardNavigationGestures = true

        // Present a Safari-like User-Agent to improve compatibility with sites
        // that sniff for Safari specifically (e.g., Google properties).
        webView.customUserAgent = WebViewRegistry.safariLikeUserAgent()

        let controller = WebTabController(objectId: objectId, onMetadata: onMetadata)
        controller.attach(to: webView)

        if let cmw = webView as? ContextMenuWebView {
            cmw.actionHandler = controller
        }

        webView.load(URLRequest(url: initialURL))
        entries[objectId] = Entry(webView: webView, controller: controller)
        return webView
    }

    func webView(for objectId: UUID) -> WKWebView? {
        entries[objectId]?.webView
    }

    func remove(objectId: UUID) {
        if let entry = entries.removeValue(forKey: objectId) {
            // Mark controller as cleaned up to prevent callbacks
            entry.controller.markAsCleanedUp()
            // Proactively close any popup windows associated with this controller
            entry.controller.closeAllPopups()
            // Try to explicitly stop media playback (video/audio) before tearing down
            // This prevents background audio (e.g., YouTube) continuing after tab close
            let pauseJS = "document.querySelectorAll('video,audio').forEach(function(m){try{m.pause();m.src='';m.load()}catch(e){}});"
            entry.webView.evaluateJavaScript(pauseJS, completionHandler: nil)
            // Navigate to a blank document to fully detach media pipelines
            entry.webView.loadHTMLString("", baseURL: nil)
            entry.webView.navigationDelegate = nil
            entry.webView.uiDelegate = nil
            // Remove script message handlers we added
            entry.webView.configuration.userContentController.removeScriptMessageHandler(forName: "inPageNavigation")
            entry.webView.configuration.userContentController.removeScriptMessageHandler(forName: "blobDownload")
            entry.webView.configuration.userContentController.removeScriptMessageHandler(forName: "consoleLog")
            entry.webView.removeFromSuperviewWithoutNeedingDisplay()
        }
    }

    func sync(with objectIds: Set<UUID>) {
        // Remove any entries no longer represented
        let existing = Set(entries.keys)
        let toRemove = existing.subtracting(objectIds)
        toRemove.forEach { remove(objectId: $0) }
    }
    
    func clearAll() {
        // Remove all WebViews (used when exiting a task)
        let allIds = Array(entries.keys)
        allIds.forEach { remove(objectId: $0) }
        #if DEBUG
        print("[WebViewRegistry] Cleared all \(allIds.count) WebViews and associated popups")
        #endif
    }
    
    func navigateTo(objectId: UUID, url: URL) {
        // Explicitly navigate a WebView to a new URL (e.g., from Cmd+L)
        if let entry = entries[objectId] {
            entry.webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - User-Agent utilities
extension WebViewRegistry {
    static func safariLikeUserAgent() -> String {
        // Construct a conservative, Safari-like UA string.
        // Apple keeps the AppleWebKit/Safari build numbers stable for
        // compatibility; the exact Safari Version number is less critical
        // for most sniffers compared to the presence of "Safari" tokens.
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(v.majorVersion)_\(v.minorVersion)_\(v.patchVersion)"
        // Example: Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(os)) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }
}

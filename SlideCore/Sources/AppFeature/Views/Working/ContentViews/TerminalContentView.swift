import SlideCLICore
import SlideDatabase
import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers

// MARK: - Notification Names

extension Notification.Name {
    static let terminalOSCNotification = Notification.Name("TerminalOSCNotification")
    static let terminalTitleChanged = Notification.Name("TerminalTitleChanged")
}

// MARK: - Terminal Process Delegate

/// Receives title changes (OSC 0/2) from SwiftTerm and posts them as notifications.
final class TerminalProcessDelegate: LocalProcessTerminalViewDelegate {
    let objectId: UUID

    init(objectId: UUID) {
        self.objectId = objectId
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [objectId] in
            NotificationCenter.default.post(
                name: .terminalTitleChanged,
                object: nil,
                userInfo: ["objectId": objectId, "title": title]
            )
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}

// MARK: - Layout-safe Terminal View

/// Subclass that overrides `insertText` (which IS `open`) to bypass SwiftTerm's
/// Kitty keyboard protocol encoding for regular text input.
///
/// SwiftTerm's Kitty path reads `event.charactersIgnoringModifiers` and a static
/// `kittyBaseLayoutKeyMap` keyed on `event.keyCode` (physical position). On non-QWERTY
/// layouts (Dvorak, Colemak, etc.) this produces QWERTY-position characters instead of
/// layout-correct ones. Overriding `insertText` ensures the text produced by
/// `interpretKeyEvents` — which DOES respect the active keyboard layout — is always
/// sent directly to the PTY.
///
/// `keyDown` is `public` (not `open`) in SwiftTerm so we cannot override it, but
/// `insertText` is `open` and is the final text-delivery path from `interpretKeyEvents`.
final class SlideTerminalView: LocalProcessTerminalView {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    /// Track whether the current insertText call originated from a paste operation
    /// so we can still wrap it in bracketed-paste sequences.
    private var _isPasting = false

    /// Local key-event monitor for combos SwiftTerm doesn't handle
    /// (keyDown is `public`, not `open`, so we can't override it).
    private var keyEventMonitor: Any?

    deinit {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Install after the view is created. Intercepts key combos that SwiftTerm
    /// ignores and sends the expected terminal sequences.
    func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.firstResponder === self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Shift+Return → newline (multi-line input)
            if event.keyCode == 36, flags == .shift {
                self.send(txt: "\n")
                return nil
            }

            // Cmd+Delete → Ctrl+U (kill to beginning of line)
            if event.keyCode == 51, flags == .command {
                self.send(txt: "\u{15}")
                return nil
            }

            return event
        }
    }

    override func paste(_ sender: Any?) {
        _isPasting = true
        super.paste(sender)
        _isPasting = false
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let str = string as? NSString else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let text = str as String
        let terminal = getTerminal()

        if _isPasting, terminal.bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteStart[0...])
            send(txt: text)
            send(data: EscapeSequences.bracketedPasteEnd[0...])
        } else {
            send(txt: text)
        }
    }

    // MARK: - Shell quoting

    /// Wraps a path in single quotes with proper escaping for shell use.
    private func shellQuote(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Sends text into the terminal, respecting bracketed paste mode.
    private func sendPastedText(_ text: String) {
        let terminal = getTerminal()
        if terminal.bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteStart[0...])
            send(txt: text)
            send(data: EscapeSequences.bracketedPasteEnd[0...])
        } else {
            send(txt: text)
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0

        let pasteboard = sender.draggingPasteboard

        // 1. File URLs (Finder files + sidebar file-backed objects)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], let fileURL = fileURLs.first {
            sendPastedText(shellQuote(fileURL.path) + " ")
            return true
        }

        // 2. Any URL (web links from sidebar)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first {
            sendPastedText(url.absoluteString + " ")
            return true
        }

        // 3. Plain string fallback — skip bare UUIDs (from sidebar drag-only)
        if let strings = pasteboard.readObjects(forClasses: [NSString.self]) as? [String],
           let str = strings.first {
            // Skip if the string is just a UUID (sidebar backward-compat payload)
            if UUID(uuidString: str) != nil { return false }
            sendPastedText(str + " ")
            return true
        }

        return false
    }
}

// MARK: - Terminal Registry

/// Caches `SlideTerminalView` instances by object UUID so terminal sessions
/// persist across tab switches (same pattern as `WebViewRegistry` for web views).
@Observable final class TerminalRegistry {
    private var entries: [UUID: SlideTerminalView] = [:]
    private var delegates: [UUID: TerminalProcessDelegate] = [:]

    // MARK: - tmux support

    /// Path to tmux binary, if installed.
    static let tmuxPath: String? = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux"
    ].first(where: { FileManager.default.isExecutableFile(atPath: $0) })

    private static let tmuxConfigPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".slide/tmux.conf").path

    /// Writes `~/.slide/tmux.conf` if it doesn't already exist.
    private func ensureTmuxConfig() {
        let path = Self.tmuxConfigPath
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let config = """
        set -g status off
        set -g prefix None
        unbind C-b
        set -g mouse on
        set -g default-terminal "xterm-256color"
        set -g allow-passthrough on
        """
        try? config.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func ensureTerminalView(
        objectId: UUID,
        workingDirectory: String,
        projectId: UUID? = nil,
        projectName: String? = nil
    ) -> SlideTerminalView {
        if let existing = entries[objectId] { return existing }

        let terminalView = SlideTerminalView(frame: .zero)
        terminalView.registerForDraggedTypes([.fileURL, .URL, .string])
        terminalView.installKeyEventMonitor()
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.nativeForegroundColor = .white
        terminalView.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminalView.caretColor = .white

        // Set process delegate for title changes (OSC 0/2)
        let delegate = TerminalProcessDelegate(objectId: objectId)
        terminalView.processDelegate = delegate
        delegates[objectId] = delegate

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellArgs = shell.hasSuffix("zsh") ? ["--login"] : ["-l"]

        // Inject Slide environment variables for agent integration
        var env = ProcessInfo.processInfo.environment
        env["SLIDE_SOCKET_PATH"] = CommandServer.socketPath
        env["SLIDE_OBJECT_ID"] = objectId.uuidString
        if let projectId {
            env["SLIDE_PROJECT_ID"] = projectId.uuidString
        }
        if let projectName {
            env["SLIDE_PROJECT_NAME"] = projectName
        }
        // Add CLI to PATH
        let slideBinDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".slide/bin").path
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(slideBinDir):\(existingPath)"
        }

        env["TERM"] = "xterm-256color"
        let envArray = env.map { "\($0.key)=\($0.value)" }

        // Expand tilde in working directory
        let expandedDir: String
        if workingDirectory == "~" {
            expandedDir = NSHomeDirectory()
        } else {
            expandedDir = (workingDirectory as NSString).expandingTildeInPath
        }

        if let tmux = Self.tmuxPath {
            // Wrap terminal in a tmux session for persistence across app restarts
            ensureTmuxConfig()
            let sessionName = "slide-\(objectId.uuidString)"
            terminalView.startProcess(
                executable: tmux,
                args: ["-L", "slide", "-f", Self.tmuxConfigPath,
                       "new-session", "-A", "-s", sessionName, "-c", expandedDir],
                environment: envArray,
                execName: nil
            )
            // No cd needed: -c sets the dir for new sessions,
            // and reattached sessions are already in the right place
        } else {
            // Fallback: bare shell (no tmux installed)
            terminalView.startProcess(
                executable: shell,
                args: shellArgs,
                environment: envArray,
                execName: nil
            )
            let escapedDir = expandedDir.replacingOccurrences(of: "'", with: "'\\''")
            terminalView.send(txt: "cd '\(escapedDir)' && clear\n")
        }

        // Register OSC handlers for agent notifications
        let terminal = terminalView.getTerminal()
        let capturedObjectId = objectId

        // OSC 9: iTerm2/ConEmu notification — payload is just the text
        terminal.registerOscHandler(code: 9) { data in
            guard let text = String(bytes: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .terminalOSCNotification,
                    object: nil,
                    userInfo: ["objectId": capturedObjectId, "title": text, "body": ""]
                )
            }
        }

        // OSC 99: kitty notification — id=N:d=D;body
        terminal.registerOscHandler(code: 99) { data in
            guard let text = String(bytes: data, encoding: .utf8) else { return }
            // Parse kitty format: metadata;body
            let parts = text.split(separator: ";", maxSplits: 1)
            let body = parts.count > 1 ? String(parts[1]) : text
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .terminalOSCNotification,
                    object: nil,
                    userInfo: ["objectId": capturedObjectId, "title": body, "body": ""]
                )
            }
        }

        // OSC 777: rxvt-unicode — notify;title;body (already parsed by SwiftTerm, but register backup)
        terminal.registerOscHandler(code: 777) { data in
            guard let text = String(bytes: data, encoding: .utf8) else { return }
            let parts = text.components(separatedBy: ";")
            guard parts.count >= 2, parts[0] == "notify" else { return }
            let title = parts[1]
            let body = parts.count > 2 ? parts[2...].joined(separator: ";") : ""
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .terminalOSCNotification,
                    object: nil,
                    userInfo: ["objectId": capturedObjectId, "title": title, "body": body]
                )
            }
        }

        entries[objectId] = terminalView
        return terminalView
    }

    func terminalView(for objectId: UUID) -> SlideTerminalView? {
        entries[objectId]
    }

    func remove(objectId: UUID) {
        delegates.removeValue(forKey: objectId)
        if let entry = entries.removeValue(forKey: objectId) {
            entry.terminate()
            entry.removeFromSuperviewWithoutNeedingDisplay()
        }
        // Kill tmux session so the server-side process is cleaned up
        if let tmux = Self.tmuxPath {
            let sessionName = "slide-\(objectId.uuidString)"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmux)
            process.arguments = ["-L", "slide", "kill-session", "-t", sessionName]
            try? process.run()
        }
    }

    func sync(with objectIds: Set<UUID>) {
        let existing = Set(entries.keys)
        let toRemove = existing.subtracting(objectIds)
        toRemove.forEach { remove(objectId: $0) }
    }

    func clearAll() {
        let allIds = Array(entries.keys)
        allIds.forEach { remove(objectId: $0) }
        delegates.removeAll()
        #if DEBUG
        print("[TerminalRegistry] Cleared all \(allIds.count) terminal views")
        #endif
    }
}

// MARK: - Terminal View Host (re-parents existing terminal view)

/// Minimal `NSViewRepresentable` that re-parents an existing terminal view
/// into the SwiftUI hierarchy without recreating it — same pattern as `WebViewHost`.
struct TerminalViewHost: NSViewRepresentable {
    let terminalView: SlideTerminalView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.focusRingType = .none
        attach(terminalView, to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if terminalView.superview !== nsView {
            nsView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
            terminalView.removeFromSuperviewWithoutNeedingDisplay()
            attach(terminalView, to: nsView)
        }
        // Restore first responder so the terminal is immediately interactive
        DispatchQueue.main.async {
            if let window = nsView.window, window.firstResponder !== terminalView {
                window.makeFirstResponder(terminalView)
            }
        }
    }

    private func attach(_ terminalView: NSView, to container: NSView) {
        container.addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

// MARK: - Terminal Content View

struct TerminalContentView: View {
    let object: TaskObject
    let terminalRegistry: TerminalRegistry
    var projectId: UUID? = nil
    var projectName: String? = nil

    var body: some View {
        let terminalView = terminalRegistry.ensureTerminalView(
            objectId: object.uuidValue,
            workingDirectory: terminalWorkingDirectory,
            projectId: projectId,
            projectName: projectName
        )
        TerminalViewHost(terminalView: terminalView)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: .webFindNext)) { note in
                guard let noteObjectId = note.userInfo?[WebFindKeys.objectId] as? UUID,
                      noteObjectId == object.uuidValue else { return }
                let query = (note.userInfo?[WebFindKeys.query] as? String) ?? ""
                if query.isEmpty { return }
                let _ = terminalView.findNext(query)
            }
            .onReceive(NotificationCenter.default.publisher(for: .webFindPrevious)) { note in
                guard let noteObjectId = note.userInfo?[WebFindKeys.objectId] as? UUID,
                      noteObjectId == object.uuidValue else { return }
                let query = (note.userInfo?[WebFindKeys.query] as? String) ?? ""
                if query.isEmpty { return }
                let _ = terminalView.findPrevious(query)
            }
    }

    private var terminalWorkingDirectory: String {
        if case .terminal(let data) = object.payload {
            let dir = data.workingDirectory
            if dir == "~" {
                return NSHomeDirectory()
            }
            return (dir as NSString).expandingTildeInPath
        }
        return NSHomeDirectory()
    }
}

// MARK: - Drag Item Provider

extension TaskObject {
    /// Creates an `NSItemProvider` that always carries the UUID string (for sidebar→rail drops)
    /// plus a richer representation depending on the object kind.
    func dragItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()

        // Always register UUID as a plain string (backward-compat with ProjectRailView drops)
        provider.registerObject(uuid as NSString, visibility: .all)

        switch payload {
        case .pdf(let d):
            let fileURL = URL(fileURLWithPath: d.filePath) as NSURL
            provider.registerObject(fileURL, visibility: .all)

        case .image(let d):
            let fileURL = URL(fileURLWithPath: d.filePath) as NSURL
            provider.registerObject(fileURL, visibility: .all)

        case .video(let d):
            let fileURL = URL(fileURLWithPath: d.filePath) as NSURL
            provider.registerObject(fileURL, visibility: .all)

        case .audio(let d):
            let fileURL = URL(fileURLWithPath: d.filePath) as NSURL
            provider.registerObject(fileURL, visibility: .all)

        case .codeEditor(let d):
            if let filePath = d.filePath {
                let fileURL = URL(fileURLWithPath: filePath) as NSURL
                provider.registerObject(fileURL, visibility: .all)
            }

        case .terminal(let d):
            let dir = d.workingDirectory == "~"
                ? NSHomeDirectory()
                : (d.workingDirectory as NSString).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: dir) as NSURL
            provider.registerObject(fileURL, visibility: .all)

        case .link:
            if let webURL = url {
                provider.registerObject(webURL as NSURL, visibility: .all)
            }

        case .note, .group, .invalid:
            break
        }

        return provider
    }
}

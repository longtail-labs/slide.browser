import AppKit
import GhosttyTerminal
import SlideCLICore
import SlideDatabase
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Notification Names

extension Notification.Name {
    static let terminalOSCNotification = Notification.Name("TerminalOSCNotification")
    static let terminalTitleChanged = Notification.Name("TerminalTitleChanged")
}

// MARK: - Terminal Registry

/// Caches Ghostty terminal entries by object UUID so sessions persist across tab switches.
@MainActor
@Observable final class TerminalRegistry {
    private var entries: [UUID: GhosttyTerminalEntry] = [:]

    static let tmuxPath: String? = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
    ].first(where: { FileManager.default.isExecutableFile(atPath: $0) })

    private static let tmuxSocketName = "slide"
    private static let tmuxConfigPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".slide/tmux.conf").path

    private static let utf8Locale = "en_US.UTF-8"
    private static let defaultFontSize: Float = 15

    func ensureTerminalEntry(
        objectId: UUID,
        workingDirectory: String,
        shell: String? = nil,
        projectId: UUID? = nil,
        projectName: String? = nil
    ) -> GhosttyTerminalEntry {
        if let existing = entries[objectId] {
            return existing
        }

        let expandedDirectory = expandWorkingDirectory(workingDirectory)
        let launchConfiguration = makeLaunchConfiguration(
            objectId: objectId,
            workingDirectory: expandedDirectory,
            shell: shell,
            projectId: projectId,
            projectName: projectName
        )

        let entry = GhosttyTerminalEntry(
            objectId: objectId,
            workingDirectory: expandedDirectory,
            controller: makeTerminalController(),
            fontSize: Self.defaultFontSize,
            launchConfiguration: launchConfiguration
        )

        entries[objectId] = entry
        return entry
    }

    func terminalEntry(for objectId: UUID) -> GhosttyTerminalEntry? {
        entries[objectId]
    }

    func remove(objectId: UUID) {
        guard let entry = entries.removeValue(forKey: objectId) else { return }
        entry.terminate()
    }

    func sync(with objectIds: Set<UUID>) {
        let existing = Set(entries.keys)
        let toRemove = existing.subtracting(objectIds)
        toRemove.forEach { remove(objectId: $0) }
    }

    func clearAll() {
        let allIds = Array(entries.keys)
        allIds.forEach { remove(objectId: $0) }
        #if DEBUG
        print("[TerminalRegistry] Cleared all \(allIds.count) terminal views")
        #endif
    }

    private func makeLaunchConfiguration(
        objectId: UUID,
        workingDirectory: String,
        shell: String?,
        projectId: UUID?,
        projectName: String?
    ) -> GhosttyLaunchConfiguration {
        let environment = makeEnvironment(
            objectId: objectId,
            projectId: projectId,
            projectName: projectName
        )
        let envArray = environment.map { "\($0.key)=\($0.value)" }

        if let tmuxPath = Self.tmuxPath {
            ensureTmuxConfig()
            let sessionName = tmuxSessionName(for: objectId)
            return GhosttyLaunchConfiguration(
                executable: tmuxPath,
                args: [
                    "-u",
                    "-L", Self.tmuxSocketName,
                    "-f", Self.tmuxConfigPath,
                    "new-session",
                    "-A",
                    "-s", sessionName,
                    "-c", workingDirectory,
                ],
                environment: envArray,
                currentDirectory: workingDirectory,
                tmuxPath: tmuxPath,
                tmuxSocketName: Self.tmuxSocketName,
                tmuxSessionName: sessionName
            )
        }

        let shellPath = shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellArgs = shellPath.hasSuffix("zsh") ? ["--login"] : ["-l"]

        return GhosttyLaunchConfiguration(
            executable: shellPath,
            args: shellArgs,
            environment: envArray,
            currentDirectory: workingDirectory,
            tmuxPath: nil,
            tmuxSocketName: nil,
            tmuxSessionName: nil
        )
    }

    private func makeTerminalController() -> TerminalController {
        TerminalController { builder in
            builder.withFontSize(Self.defaultFontSize)
            // Native selection/copy is the priority for embedded Slide terminals.
            builder.withCustom("copy-on-select", "clipboard")
            builder.withCustom("selection-clear-on-copy", "false")
            builder.withCustom("mouse-reporting", "false")
            builder.withCustom("right-click-action", "copy-or-paste")
        }
    }

    private func makeEnvironment(
        objectId: UUID,
        projectId: UUID?,
        projectName: String?
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        env["SLIDE_SOCKET_PATH"] = CommandServer.socketPath
        env["SLIDE_OBJECT_ID"] = objectId.uuidString

        if let projectId {
            env["SLIDE_PROJECT_ID"] = projectId.uuidString
        }
        if let projectName {
            env["SLIDE_PROJECT_NAME"] = projectName
        }

        let slideBinDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".slide/bin").path
        if let existingPath = env["PATH"], !existingPath.isEmpty {
            env["PATH"] = "\(slideBinDir):\(existingPath)"
        } else {
            env["PATH"] = slideBinDir
        }

        if env["LANG"]?.isEmpty != false {
            env["LANG"] = Self.utf8Locale
        }
        if env["LC_CTYPE"]?.isEmpty != false {
            env["LC_CTYPE"] = Self.utf8Locale
        }

        env["TERM"] = "xterm-256color"
        return env
    }

    private func expandWorkingDirectory(_ workingDirectory: String) -> String {
        if workingDirectory == "~" {
            return NSHomeDirectory()
        }
        return (workingDirectory as NSString).expandingTildeInPath
    }

    private func tmuxSessionName(for objectId: UUID) -> String {
        "slide-\(objectId.uuidString)"
    }

    /// Writes `~/.slide/tmux.conf` so Ghostty tabs use native selection and tmux can surface titles.
    private func ensureTmuxConfig() {
        let path = Self.tmuxConfigPath
        let config = """
        set -g status off
        set -g prefix None
        unbind C-b
        set -g mouse off
        set -g default-terminal "xterm-256color"
        set -g allow-passthrough on
        set -g allow-rename on
        set -g set-titles on
        set -g set-titles-string "#{?pane_title,#{pane_title},#{pane_current_command}}"
        set -s set-clipboard on
        """

        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? config.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Terminal View Host

@MainActor
fileprivate final class GhosttyTerminalHostView: NSView {
    private var terminalEntry: GhosttyTerminalEntry?
    private var keyEventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = true
        registerForDraggedTypes([.fileURL, .URL, .string])
        installKeyEventMonitor()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFirstResponder()
    }

    override func layout() {
        super.layout()
        terminalEntry?.terminalView.frame = bounds
    }

    func updateTerminalEntry(_ terminalEntry: GhosttyTerminalEntry) {
        self.terminalEntry = terminalEntry

        if terminalEntry.terminalView.superview !== self {
            subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
            terminalEntry.terminalView.removeFromSuperviewWithoutNeedingDisplay()
            attach(terminalEntry.terminalView)
        }

        terminalEntry.activateIfNeeded()
        requestFirstResponder()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard droppedText(from: sender.draggingPasteboard) != nil else { return [] }
        highlightDropTarget(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedText(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        highlightDropTarget(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { highlightDropTarget(false) }
        guard let text = droppedText(from: sender.draggingPasteboard) else { return false }
        terminalEntry?.sendText(text)
        return true
    }

    private func attach(_ terminalView: NSView) {
        terminalView.frame = bounds
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
    }

    private func requestFirstResponder() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let terminalView = self.terminalEntry?.terminalView,
                  let window = self.window,
                  window.firstResponder !== terminalView
            else { return }
            window.makeFirstResponder(terminalView)
        }
    }

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let terminalView = self.terminalEntry?.terminalView,
                  self.window?.firstResponder === terminalView
            else {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 36, flags == .shift {
                self.terminalEntry?.sendText("\n")
                return nil
            }

            if event.keyCode == 51, flags == .command {
                self.terminalEntry?.sendInput(Data([0x15]))
                return nil
            }

            return event
        }
    }

    private func highlightDropTarget(_ isHighlighted: Bool) {
        layer?.borderWidth = isHighlighted ? 2 : 0
        layer?.borderColor = isHighlighted ? NSColor.controlAccentColor.cgColor : nil
    }

    private func droppedText(from pasteboard: NSPasteboard) -> String? {
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let fileURL = fileURLs.first {
            return shellQuote(fileURL.path) + " "
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first {
            return url.absoluteString + " "
        }

        if let strings = pasteboard.readObjects(forClasses: [NSString.self]) as? [String],
           let string = strings.first {
            if UUID(uuidString: string) != nil {
                return nil
            }
            return string + " "
        }

        return nil
    }

    private func shellQuote(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

/// Re-parents an existing Ghostty terminal view into SwiftUI without recreating it.
@MainActor
fileprivate struct TerminalViewHost: NSViewRepresentable {
    let terminalEntry: GhosttyTerminalEntry

    func makeNSView(context: Context) -> GhosttyTerminalHostView {
        let container = GhosttyTerminalHostView(frame: .zero)
        container.updateTerminalEntry(terminalEntry)
        return container
    }

    func updateNSView(_ nsView: GhosttyTerminalHostView, context: Context) {
        nsView.updateTerminalEntry(terminalEntry)
    }
}

// MARK: - Terminal Content View

struct TerminalContentView: View {
    let object: TaskObject
    let terminalRegistry: TerminalRegistry
    var projectId: UUID? = nil
    var projectName: String? = nil

    var body: some View {
        let terminalEntry = terminalRegistry.ensureTerminalEntry(
            objectId: object.uuidValue,
            workingDirectory: terminalWorkingDirectory,
            shell: terminalShell,
            projectId: projectId,
            projectName: projectName
        )

        TerminalViewHost(terminalEntry: terminalEntry)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalWorkingDirectory: String {
        guard case .terminal(let data) = object.payload else {
            return NSHomeDirectory()
        }
        return data.workingDirectory
    }

    private var terminalShell: String? {
        guard case .terminal(let data) = object.payload else { return nil }
        return data.shell
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

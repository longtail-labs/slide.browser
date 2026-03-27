import Foundation
import GhosttyTerminal

#if DEBUG
private func debugTerminalTitle(_ message: String) {
    print("[TerminalTitle] \(message)")
}
#else
private func debugTerminalTitle(_ message: String) {}
#endif

private final class GhosttyProcessBox: @unchecked Sendable {
    weak var value: GhosttyTerminalProcessBridge?
}

private final class TerminalOSCParser {
    typealias TitleHandler = @Sendable (String) -> Void
    typealias NotificationHandler = @Sendable (String, String) -> Void

    private enum State {
        case normal
        case escape
        case osc
        case oscEscape
    }

    private static let esc: UInt8 = 0x1B
    private static let osc: UInt8 = 0x5D
    private static let bell: UInt8 = 0x07
    private static let stringTerminator: UInt8 = 0x5C
    private static let semicolon: UInt8 = 0x3B
    private static let maxPayloadBytes = 16 * 1024

    private let objectId: UUID
    private let onTitleChange: TitleHandler
    private let onNotification: NotificationHandler
    private var state: State = .normal
    private var buffer: [UInt8] = []

    init(
        objectId: UUID,
        onTitleChange: @escaping TitleHandler,
        onNotification: @escaping NotificationHandler
    ) {
        self.objectId = objectId
        self.onTitleChange = onTitleChange
        self.onNotification = onNotification
    }

    func consume(_ data: Data) {
        for byte in data {
            switch state {
            case .normal:
                if byte == Self.esc {
                    state = .escape
                }

            case .escape:
                if byte == Self.osc {
                    buffer.removeAll(keepingCapacity: true)
                    state = .osc
                } else if byte == Self.esc {
                    state = .escape
                } else {
                    state = .normal
                }

            case .osc:
                if byte == Self.bell {
                    finishOSC()
                } else if byte == Self.esc {
                    state = .oscEscape
                } else {
                    append(byte)
                }

            case .oscEscape:
                if byte == Self.stringTerminator {
                    finishOSC()
                } else {
                    append(Self.esc)
                    append(byte)
                    state = .osc
                }
            }
        }
    }

    private func append(_ byte: UInt8) {
        guard buffer.count < Self.maxPayloadBytes else {
            buffer.removeAll(keepingCapacity: true)
            state = .normal
            return
        }
        buffer.append(byte)
    }

    private func finishOSC() {
        let payload = buffer
        buffer.removeAll(keepingCapacity: true)
        state = .normal
        handle(payload)
    }

    private func handle(_ payload: [UInt8]) {
        guard let separatorIndex = payload.firstIndex(of: Self.semicolon) else { return }
        guard let code = Int(String(decoding: payload[..<separatorIndex], as: UTF8.self)) else { return }
        let textBytes = payload[payload.index(after: separatorIndex)...]
        guard let text = String(bytes: textBytes, encoding: .utf8) else { return }

        if [0, 2, 9, 99, 777].contains(code) {
            debugTerminalTitle("Parsed OSC \(code) for \(objectId): \(text)")
        }

        switch code {
        case 0, 2:
            onTitleChange(text)

        case 9:
            onNotification(text, "")

        case 99:
            let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            let body = parts.count > 1 ? String(parts[1]) : text
            onNotification(body, "")

        case 777:
            let parts = text.components(separatedBy: ";")
            guard parts.count >= 2, parts[0] == "notify" else { return }
            let title = parts[1]
            let body = parts.count > 2 ? parts[2...].joined(separator: ";") : ""
            onNotification(title, body)

        default:
            break
        }
    }
}

struct GhosttyLaunchConfiguration: Sendable {
    let executable: String
    let args: [String]
    let environment: [String]
    let currentDirectory: String?
    let tmuxPath: String?
    let tmuxSocketName: String?
    let tmuxSessionName: String?
}

final class GhosttyTerminalProcessBridge: SlidePTYProcessDelegate, @unchecked Sendable {
    private enum ResolvedTitleSource: String {
        case osc
        case ghosttyDelegate = "ghostty_delegate"
        case tmuxPaneTitle = "tmux_pane_title"
        case tmuxCurrentCommand = "tmux_current_command"
        case idleDefault = "idle_default"
    }

    private struct TmuxTitleSnapshot {
        let paneTitle: String
        let currentCommand: String
        let currentPath: String
    }

    private static let tmuxFieldSeparator = Character("\u{1F}")
    private static let tmuxQueryDelay: TimeInterval = 0.2
    private static let defaultIdleTitle = "Terminal"
    private static let idleCommands: Set<String> = [
        "",
        "fish",
        "zsh",
        "bash",
        "sh",
        "tmux",
        "login",
        "env",
    ]

    private let lock = NSLock()
    private let objectId: UUID
    private let session: InMemoryTerminalSession
    private let launchConfiguration: GhosttyLaunchConfiguration
    private var viewport = InMemoryTerminalViewport(columns: 80, rows: 24)
    private var hasStarted = false
    private var didFinish = false
    private var startedAt = Date()
    private var tmuxSyncWorkItem: DispatchWorkItem?
    private var lastResolvedTitle: String?
    private var lastResolvedTitleSource: ResolvedTitleSource?
    private lazy var process = SlidePTYProcess(delegate: self)
    private lazy var oscParser = TerminalOSCParser(
        objectId: objectId,
        onTitleChange: { [weak self] title in
            self?.publishResolvedTitle(title, source: .osc)
        },
        onNotification: { [weak self] title, body in
            self?.postOSCNotification(title: title, body: body)
        }
    )

    init(
        objectId: UUID,
        session: InMemoryTerminalSession,
        launchConfiguration: GhosttyLaunchConfiguration
    ) {
        self.objectId = objectId
        self.session = session
        self.launchConfiguration = launchConfiguration
    }

    func startIfNeeded() {
        lock.lock()
        guard !hasStarted else {
            lock.unlock()
            return
        }
        hasStarted = true
        didFinish = false
        startedAt = Date()
        lock.unlock()

        process.start(
            executable: launchConfiguration.executable,
            args: launchConfiguration.args,
            environment: launchConfiguration.environment,
            currentDirectory: launchConfiguration.currentDirectory
        )

        scheduleTmuxTitleSync(reason: "start")
    }

    func sendInput(_ data: Data) {
        process.send(data)
        scheduleTmuxTitleSync(reason: "input")
    }

    func updateViewport(_ viewport: InMemoryTerminalViewport) {
        lock.lock()
        self.viewport = viewport
        lock.unlock()

        guard process.isRunning else { return }
        process.resize(windowSize: makeWindowSize(from: viewport))
    }

    func terminate() {
        cancelPendingTmuxSync()
        process.terminate()
        killTmuxSessionIfNeeded()
    }

    func initialWindowSize(for process: SlidePTYProcess) -> winsize {
        lock.lock()
        let viewport = viewport
        lock.unlock()
        return makeWindowSize(from: viewport)
    }

    func ptyProcess(_ process: SlidePTYProcess, didReceive data: Data) {
        oscParser.consume(data)
        session.receive(data)
        scheduleTmuxTitleSync(reason: "pty_output")
    }

    func ptyProcess(_ process: SlidePTYProcess, didTerminateWith exitCode: Int32?) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        tmuxSyncWorkItem?.cancel()
        tmuxSyncWorkItem = nil
        let runtimeMs = max(0, Date().timeIntervalSince(startedAt) * 1000)
        lock.unlock()

        session.finish(
            exitCode: UInt32(bitPattern: exitCode ?? 0),
            runtimeMilliseconds: UInt64(runtimeMs.rounded())
        )
    }

    private func makeWindowSize(from viewport: InMemoryTerminalViewport) -> winsize {
        winsize(
            ws_row: viewport.rows,
            ws_col: viewport.columns,
            ws_xpixel: UInt16(clamping: viewport.widthPixels),
            ws_ypixel: UInt16(clamping: viewport.heightPixels)
        )
    }

    func handleGhosttyTitle(_ title: String) {
        publishResolvedTitle(title, source: .ghosttyDelegate)
    }

    private func publishResolvedTitle(_ title: String, source: ResolvedTitleSource) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        lock.lock()
        if lastResolvedTitle == normalizedTitle, lastResolvedTitleSource == source {
            lock.unlock()
            return
        }
        lastResolvedTitle = normalizedTitle
        lastResolvedTitleSource = source
        lock.unlock()

        debugTerminalTitle("Resolved \(source.rawValue) for \(objectId): \(normalizedTitle)")

        DispatchQueue.main.async { [objectId] in
            NotificationCenter.default.post(
                name: .terminalTitleChanged,
                object: nil,
                userInfo: [
                    "objectId": objectId,
                    "title": normalizedTitle,
                ]
            )
        }
    }

    private func postOSCNotification(title: String, body: String) {
        DispatchQueue.main.async { [objectId] in
            NotificationCenter.default.post(
                name: .terminalOSCNotification,
                object: nil,
                userInfo: [
                    "objectId": objectId,
                    "title": title,
                    "body": body,
                ]
            )
        }
    }

    private func scheduleTmuxTitleSync(reason: String) {
        guard launchConfiguration.tmuxPath != nil,
              launchConfiguration.tmuxSocketName != nil,
              launchConfiguration.tmuxSessionName != nil else { return }

        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        tmuxSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.queryTmuxTitle(reason: reason)
        }
        tmuxSyncWorkItem = workItem
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.tmuxQueryDelay,
            execute: workItem
        )
    }

    private func cancelPendingTmuxSync() {
        lock.lock()
        tmuxSyncWorkItem?.cancel()
        tmuxSyncWorkItem = nil
        lock.unlock()
    }

    private func queryTmuxTitle(reason: String) {
        guard process.isRunning else { return }
        guard let snapshot = fetchTmuxTitleSnapshot() else {
            debugTerminalTitle("tmux query \(reason) for \(objectId) returned no data")
            return
        }

        debugTerminalTitle(
            "tmux \(reason) for \(objectId): paneTitle='\(snapshot.paneTitle)' current='\(snapshot.currentCommand)' path='\(snapshot.currentPath)'"
        )

        let (title, source) = resolveTitle(from: snapshot)
        publishResolvedTitle(title, source: source)
    }

    private func fetchTmuxTitleSnapshot() -> TmuxTitleSnapshot? {
        guard let tmuxPath = launchConfiguration.tmuxPath,
              let tmuxSocketName = launchConfiguration.tmuxSocketName,
              let sessionName = launchConfiguration.tmuxSessionName else { return nil }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let fieldSeparator = String(Self.tmuxFieldSeparator)
        let format = "#{pane_title}\(fieldSeparator)#{pane_current_command}\(fieldSeparator)#{pane_current_path}"

        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = [
            "-L",
            tmuxSocketName,
            "display-message",
            "-p",
            "-t",
            sessionName,
            format,
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            debugTerminalTitle("tmux query failed to start for \(objectId): \(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()

        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errorText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            debugTerminalTitle("tmux query failed for \(objectId): \(errorText)")
            return nil
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .newlines) else { return nil }

        let parts = output.split(
            separator: Self.tmuxFieldSeparator,
            maxSplits: 2,
            omittingEmptySubsequences: false
        )

        let paneTitle = parts.indices.contains(0) ? String(parts[0]) : ""
        let currentCommand = parts.indices.contains(1) ? String(parts[1]) : ""
        let currentPath = parts.indices.contains(2) ? String(parts[2]) : ""

        return TmuxTitleSnapshot(
            paneTitle: paneTitle,
            currentCommand: currentCommand,
            currentPath: currentPath
        )
    }

    private func resolveTitle(from snapshot: TmuxTitleSnapshot) -> (String, ResolvedTitleSource) {
        let paneTitle = snapshot.paneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !paneTitle.isEmpty {
            return (paneTitle, .tmuxPaneTitle)
        }

        let currentCommand = snapshot.currentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !Self.idleCommands.contains(currentCommand.lowercased()) {
            return (currentCommand, .tmuxCurrentCommand)
        }

        return (Self.defaultIdleTitle, .idleDefault)
    }

    private func killTmuxSessionIfNeeded() {
        guard let tmuxPath = launchConfiguration.tmuxPath,
              let tmuxSocketName = launchConfiguration.tmuxSocketName,
              let sessionName = launchConfiguration.tmuxSessionName else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["-L", tmuxSocketName, "kill-session", "-t", sessionName]
        try? process.run()
    }
}

@MainActor
final class GhosttyTerminalDelegateBridge:
    NSObject,
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceGridResizeDelegate,
    TerminalSurfaceCloseDelegate
{
    private let objectId: UUID
    private let processBridge: GhosttyTerminalProcessBridge

    init(objectId: UUID, processBridge: GhosttyTerminalProcessBridge) {
        self.objectId = objectId
        self.processBridge = processBridge
    }

    func terminalDidChangeTitle(_ title: String) {
        guard !title.isEmpty else { return }
        debugTerminalTitle("Ghostty delegate title for \(objectId): \(title)")
        processBridge.handleGhosttyTitle(title)
    }

    func terminalDidResize(_ size: TerminalGridMetrics) {
        processBridge.updateViewport(
            InMemoryTerminalViewport(
                columns: size.columns,
                rows: size.rows,
                widthPixels: size.widthPixels,
                heightPixels: size.heightPixels,
                cellWidthPixels: size.cellWidthPixels,
                cellHeightPixels: size.cellHeightPixels
            )
        )
    }

    func terminalDidClose(processAlive _: Bool) {}
}

@MainActor
final class GhosttyTerminalEntry {
    let terminalView: GhosttyTerminal.TerminalView

    private let session: InMemoryTerminalSession
    private let processBridge: GhosttyTerminalProcessBridge
    private let delegateBridge: GhosttyTerminalDelegateBridge

    init(
        objectId: UUID,
        workingDirectory: String,
        controller: TerminalController,
        fontSize: Float,
        launchConfiguration: GhosttyLaunchConfiguration
    ) {
        let processBox = GhosttyProcessBox()
        let session = InMemoryTerminalSession(
            write: { data in
                processBox.value?.sendInput(data)
            },
            resize: { viewport in
                processBox.value?.updateViewport(viewport)
            }
        )

        let processBridge = GhosttyTerminalProcessBridge(
            objectId: objectId,
            session: session,
            launchConfiguration: launchConfiguration
        )
        processBox.value = processBridge

        let delegateBridge = GhosttyTerminalDelegateBridge(
            objectId: objectId,
            processBridge: processBridge
        )

        let terminalView = GhosttyTerminal.TerminalView(frame: .zero)
        terminalView.delegate = delegateBridge
        terminalView.controller = controller
        terminalView.configuration = TerminalSurfaceOptions(
            backend: .inMemory(session),
            fontSize: fontSize,
            workingDirectory: workingDirectory
        )

        self.terminalView = terminalView
        self.session = session
        self.processBridge = processBridge
        self.delegateBridge = delegateBridge
    }

    func activateIfNeeded() {
        terminalView.fitToSize()
        processBridge.startIfNeeded()
    }

    func sendInput(_ data: Data) {
        session.sendInput(data)
    }

    func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        session.sendInput(data)
    }

    func terminate() {
        processBridge.terminate()
        terminalView.removeFromSuperviewWithoutNeedingDisplay()
        _ = delegateBridge
    }
}

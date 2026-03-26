import CodeMirrorEditor
import SlideDatabase
import SwiftUI
import WebKit

// MARK: - Code Editor Registry

/// Caches CodeMirror WKWebView instances by object UUID so editor state
/// persists across tab switches (same pattern as TerminalRegistry).
@MainActor @Observable final class CodeEditorRegistry {
    struct Entry {
        let vm: CodeMirrorVM
        var filePath: String?
        var language: CodeLanguage
    }

    private var entries: [UUID: Entry] = [:]

    func ensureEditor(
        objectId: UUID,
        filePath: String? = nil,
        language: String = "plain",
        content: String? = nil
    ) -> Entry {
        if let existing = entries[objectId] { return existing }

        let lang = CodeLanguage(rawValue: language) ?? .plain
        let resolvedLang: CodeLanguage
        if lang == .plain, let fp = filePath {
            resolvedLang = CodeLanguage.from(filePath: fp)
        } else {
            resolvedLang = lang
        }

        // Load content from file if file-backed
        let initialContent: String
        if let fp = filePath {
            let expanded = (fp as NSString).expandingTildeInPath
            initialContent = (try? String(contentsOfFile: expanded, encoding: .utf8)) ?? content ?? ""
        } else {
            initialContent = content ?? ""
        }

        let vm = CodeMirrorVM()
        vm.loadEditor()

        // Queue content + language to be applied once editor is ready
        vm.setContent(initialContent)
        vm.setLanguage(resolvedLang)

        let entry = Entry(vm: vm, filePath: filePath, language: resolvedLang)
        entries[objectId] = entry
        return entry
    }

    func entry(for objectId: UUID) -> Entry? {
        entries[objectId]
    }

    func remove(objectId: UUID) {
        entries.removeValue(forKey: objectId)
    }

    func sync(with objectIds: Set<UUID>) {
        let existing = Set(entries.keys)
        let toRemove = existing.subtracting(objectIds)
        toRemove.forEach { remove(objectId: $0) }
    }

    func clearAll() {
        entries.removeAll()
    }
}

// MARK: - Code Editor View Host (re-parents existing WKWebView)

struct CodeEditorViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.focusRingType = .none
        attach(webView, to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if webView.superview !== nsView {
            nsView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
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
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

// MARK: - Code Editor Content View

struct CodeEditorContentView: View {
    let object: TaskObject
    let codeEditorRegistry: CodeEditorRegistry
    let onContentUpdate: ((TaskObject) -> Void)?

    @State private var saveStatus: SaveStatus = .clean

    private enum SaveStatus {
        case clean, dirty, saving, saved
    }

    var body: some View {
        let data = object.codeEditorData
        let entry = codeEditorRegistry.ensureEditor(
            objectId: object.uuidValue,
            filePath: data?.filePath,
            language: data?.language ?? "plain",
            content: data?.content
        )

        VStack(spacing: 0) {
            // Toolbar
            editorToolbar(entry: entry, data: data)
            Divider()

            // Editor
            CodeEditorViewHost(webView: entry.vm.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("EditorSave"))) { note in
            guard let noteObjectId = note.userInfo?["objectId"] as? UUID,
                  noteObjectId == object.uuidValue else { return }
            Task { await save(entry: entry, data: data) }
        }
    }

    @ViewBuilder
    private func editorToolbar(entry: CodeEditorRegistry.Entry, data: OBXCodeEditorData?) -> some View {
        HStack(spacing: 8) {
            // File name
            if let fp = data?.filePath {
                let fileName = (fp as NSString).lastPathComponent
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            } else {
                Image(systemName: "curlybraces")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text(object.title ?? "Code Editor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            }

            // Language badge
            Text(entry.language.rawValue)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())

            Spacer()

            // Save status
            switch saveStatus {
            case .clean:
                EmptyView()
            case .dirty:
                Text("Modified")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            case .saving:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            case .saved:
                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Saved")
                        .font(.system(size: 10))
                }
                .foregroundColor(.green)
            }

            // Save button
            if data?.filePath != nil {
                Button(action: {
                    Task { await save(entry: entry, data: data) }
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func save(entry: CodeEditorRegistry.Entry, data: OBXCodeEditorData?) async {
        saveStatus = .saving
        let content = await entry.vm.getContent()

        if let fp = data?.filePath {
            // File-backed: write to disk
            let expanded = (fp as NSString).expandingTildeInPath
            do {
                try content.write(toFile: expanded, atomically: true, encoding: .utf8)
                saveStatus = .saved
            } catch {
                print("[CodeEditor] Save failed: \(error)")
                saveStatus = .dirty
                return
            }
        } else {
            // DB-stored: update object payload
            var updated = object
            if case .codeEditor(var edData) = updated.payload {
                edData.content = content
                updated.payload = .codeEditor(edData)
                onContentUpdate?(updated)
            }
            saveStatus = .saved
        }

        // Reset status after delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if saveStatus == .saved { saveStatus = .clean }
    }
}

import ComposableArchitecture
import CommandPaletteCore
import SlideDatabase
import SwiftUI

public struct SlideAppView: View {
    @Bindable var store: StoreOf<SlideAppFeature>

    public init(store: StoreOf<SlideAppFeature>) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Project rail (Discord-style)
            ProjectRailView(store: store.scope(state: \.browser, action: \.browser))

            Divider()

            // Main content area
            VStack(spacing: 0) {
                // Filter bar
                FilterBarView(
                    store: store.scope(state: \.browser, action: \.browser),
                    onToggleCommandBar: { store.send(.toggleCommandBar) }
                )

                Divider()

                // Main content area
                HStack(spacing: 0) {
                    // Sidebar
                    if store.browser.isSidebarVisible && !store.browser.isFullscreen {
                        ContentSidebarView(store: store.scope(state: \.browser, action: \.browser))
                            .frame(width: 260)
                            .frame(maxHeight: .infinity)
                            .dropDestination(for: URL.self) { urls, _ in
                                for url in urls {
                                    importFile(url: url, store: store)
                                }
                                return !urls.isEmpty
                            }

                        Divider()
                    }

                    // Content viewer (panel strip)
                    ZStack(alignment: .topTrailing) {
                        PanelStripView(
                            store: store.scope(state: \.browser, action: \.browser)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Find bar overlay
                        if store.browser.isFindBarVisible {
                            FindBar(store: store.scope(state: \.browser, action: \.browser))
                                .padding(8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                }

                // Status bar
                if !store.browser.isFullscreen {
                    StatusBarView(store: store)
                }
            }
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowControlsVisibility(isVisible: true))
        // Command palette overlay
        .overlay {
            if let paletteStore = store.scope(state: \.commandPalette, action: \.commandPalette) {
                CommandPaletteView(store: paletteStore.scope(state: \.self, action: \.presented))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.easeOut(duration: 0.15), value: store.commandPalette != nil)
            }
        }
        .appKeyboardShortcuts(store: store)
        .browserKeyboardMonitor(store: store)
        // Browser lifecycle
        .onAppear {
            store.send(.browser(.onAppear))
        }
        // Download toast
        .onReceive(NotificationCenter.default.publisher(for: .webDownloadFinished)) { note in
            if let originId = note.userInfo?[WebFindKeys.objectId] as? UUID,
               let selectedId = store.browser.selectedObjectId,
               originId != selectedId {
                return
            }
            store.send(.showToastWithAction("Downloaded to Downloads", actionLabel: "Open Downloads", actionType: .openDownloadsFolder))
        }
        // Open links in new tab (cmd-clicked links open as new panel)
        .onReceive(NotificationCenter.default.publisher(for: .webOpenLinkInNewTab)) { note in
            guard let url = note.userInfo?["url"] as? URL else { return }
            let originId = note.userInfo?[WebFindKeys.objectId] as? UUID
            if let originId = originId,
               let selectedId = store.browser.selectedObjectId,
               originId != selectedId {
                return
            }
            let title = url.host ?? "New Tab"
            store.send(.browser(.addLinkObjectBackground(title, url)))
        }
        // Ingest finished downloads
        .onReceive(NotificationCenter.default.publisher(for: .webDownloadFinished)) { note in
            guard let fileURL = note.userInfo?["url"] as? URL else { return }
            if let originId = note.userInfo?[WebFindKeys.objectId] as? UUID,
               let selectedId = store.browser.selectedObjectId,
               originId != selectedId {
                return
            }
            let fileType = FileManager.detectFileType(for: fileURL)
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            switch fileType {
            case .pdf:
                store.send(.browser(.addPDFObject(fileName, fileURL)))
            case .image:
                store.send(.browser(.addImageObject(fileName, fileURL)))
            case .video:
                store.send(.browser(.addVideoObject(fileName, fileURL)))
            case .audio:
                store.send(.browser(.addAudioObject(fileName, fileURL)))
            case .unknown:
                break
            }
        }
        // Handle save selection to note from WebView
        .onReceive(NotificationCenter.default.publisher(for: .webSaveSelectionToNote)) { note in
            guard let _ = note.userInfo?["text"] as? String else { return }
            // TODO: wire up to note creation
        }
        // Handle search with Google
        .onReceive(NotificationCenter.default.publisher(for: .webSearchWithGoogle)) { note in
            guard let text = note.userInfo?["text"] as? String else { return }
            let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            let searchURL = URL(string: "https://www.google.com/search?q=\(query)")!
            let title = text.count > 30 ? "Google: \(text.prefix(30))..." : "Google: \(text)"
            store.send(.browser(.addLinkObject(title, searchURL)))
        }
        // Terminal title changes (OSC 0/2) → auto-rename (respects sticky customName)
        .onReceive(NotificationCenter.default.publisher(for: .terminalTitleChanged)) { note in
            guard let objectId = note.userInfo?["objectId"] as? UUID,
                  let title = note.userInfo?["title"] as? String,
                  !title.isEmpty else { return }
            store.send(.browser(.autoRenameObject(objectId, title)))
        }
        // Terminal OSC notifications → agent toast
        .onReceive(NotificationCenter.default.publisher(for: .terminalOSCNotification)) { note in
            let title = note.userInfo?["title"] as? String ?? "Notification"
            let body = note.userInfo?["body"] as? String
            let objectId = note.userInfo?["objectId"] as? UUID
            store.send(.agentToastReceived(title: title, body: body, objectId: objectId))
        }
        // Settings sheet
        .sheet(
            isPresented: Binding(
                get: { store.settings != nil },
                set: { isPresented in if !isPresented { store.send(.settings(.dismiss)) } }
            )
        ) {
            SettingsPanelContainer(appStore: store)
                .frame(width: 720, height: 520)
        }
        // Toast overlay
        .overlay(alignment: .top) {
            if let message = store.toastMessage {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.callout)

                    if let actionLabel = store.toastActionLabel {
                        Divider()
                            .frame(height: 20)

                        Button(action: {
                            store.send(.toastActionTapped)
                        }) {
                            Text(actionLabel)
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.slideAccent)
                        }
                        .buttonStyle(.plain)
                        .pointerHandCursor()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        // Agent toast overlay (bottom-right)
        .overlay(alignment: .bottomTrailing) {
            if let title = store.agentToastTitle {
                AgentToastView(
                    title: title,
                    message: store.agentToastBody,
                    hasGoTo: store.agentToastObjectId != nil,
                    onGoTo: { store.send(.agentToastGoTo) },
                    onDismiss: { store.send(.agentToastDismissed) }
                )
                .padding(16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.agentToastTitle != nil)
        .animation(.spring(response: 0.16, dampingFraction: 0.9, blendDuration: 0), value: store.browser.isFullscreen)
        .animation(.spring(response: 0.16, dampingFraction: 0.9, blendDuration: 0), value: store.browser.isSidebarVisible)
    }
}

// MARK: - Settings Panel Container

private struct SettingsPanelContainer: View {
    @Bindable var appStore: StoreOf<SlideAppFeature>

    var body: some View {
        if let settingsStore = appStore.scope(state: \.settings, action: \.settings) {
            SettingsView(store: settingsStore.scope(state: \.self, action: \.presented))
        } else {
            EmptyView()
        }
    }
}

// MARK: - Find Bar

private struct FindBar: View {
    @Bindable var store: StoreOf<ContentBrowserFeature>
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Find on page", text: Binding(
                get: { store.findQuery },
                set: { store.send(.setFindQuery($0)) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
            .focused($focused)
            .onSubmit { store.send(.findNext) }

            Button(action: { store.send(.findPrevious) }) { Image(systemName: "chevron.up") }
                .buttonStyle(.bordered)
            Button(action: { store.send(.findNext) }) { Image(systemName: "chevron.down") }
                .buttonStyle(.bordered)

            Rectangle()
                .frame(width: 1, height: 18)
                .foregroundStyle(Color(NSColor.separatorColor).opacity(0.6))

            Button(action: { store.send(.hideFindBar) }) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .fixedSize()
        .onAppear { focused = true }
        .onChange(of: store.isFindBarVisible) { _, visible in if visible { focused = true } }
    }
}

// MARK: - File Import Helper

private func importFile(url: URL, store: StoreOf<SlideAppFeature>) {
    let fileType = FileManager.detectFileType(for: url)
    let fileName = url.deletingPathExtension().lastPathComponent
    switch fileType {
    case .pdf:
        store.send(.browser(.addPDFObject(fileName, url)))
    case .image:
        store.send(.browser(.addImageObject(fileName, url)))
    case .video:
        store.send(.browser(.addVideoObject(fileName, url)))
    case .audio:
        store.send(.browser(.addAudioObject(fileName, url)))
    case .unknown:
        // Treat text-like files as notes
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            store.send(.browser(.addNoteObject(fileName, content)))
        }
    }
}

// MARK: - Transitions

extension AnyTransition {
    static var quickPopIn: AnyTransition {
        .modifier(
            active: ScaleOffsetOpacityModifier(scale: 0.96, y: 10, opacity: 1.0),
            identity: ScaleOffsetOpacityModifier(scale: 1.0, y: 0, opacity: 1.0)
        )
    }
}

struct ScaleOffsetOpacityModifier: ViewModifier {
    let scale: CGFloat
    let y: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: y)
            .opacity(opacity)
    }
}

// MARK: - Preview

#Preview("Slide – Keyboard Library") {
    let sampleObjects = {
        let primary = TaskObject.createLink(title: "Slide Design Board", url: URL(string: "https://example.com/design")!)

        let note = TaskObject.createNote(title: "Research Scratchpad", content: "Use projects as scope, not structure.")

        let child = TaskObject.createLink(title: "Arc Notes", url: URL(string: "https://example.com/arc")!)

        return [primary, note, child]
    }()

    let store = Store(
        initialState: {
            var state = SlideAppFeature.State()
            state.browser.objects = sampleObjects
            state.browser.searchQuery = "slide"
            state.browser.visiblePanelIds = [sampleObjects[0].uuidValue, sampleObjects[1].uuidValue]
            state.browser.focusedPanelIndex = 1
            return state
        }()
    ) {
        SlideAppFeature()
    } withDependencies: { values in
        values.slideDatabase.fetchAllObjects = { sampleObjects }
        values.slideDatabase.fetchAllProjects = { [] }
        values.slideDatabase.objectsStream = { AsyncStream { continuation in
            continuation.yield(sampleObjects)
            continuation.finish()
        } }
        values.slideDatabase.projectsStream = { AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        } }
    }

    SlideAppView(store: store)
}

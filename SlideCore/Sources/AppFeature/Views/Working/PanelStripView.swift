import ComposableArchitecture
import SlideDatabase
import SwiftUI
import Kingfisher

/// Horizontal strip of content panels. Each panel renders one object via TabContentView.
struct PanelStripView: View {
    let store: StoreOf<ContentBrowserFeature>
    @State var registry = WebViewRegistry()
    @State var terminalRegistry = TerminalRegistry()
    @State var codeEditorRegistry = CodeEditorRegistry()
    @State private var isActive = true

    // Prewarm threshold for link tabs (same as old ObjectContentView)
    private let warmUpThreshold = 8

    var body: some View {
        Group {
            if store.visiblePanelIds.isEmpty {
                EmptyContentView()
            } else {
                GeometryReader { geo in
                    let panelCount = min(store.visiblePanelIds.count, 2)
                    let panelWidth = max(300, geo.size.width / CGFloat(max(panelCount, 1)))

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(Array(store.visiblePanelIds.enumerated()), id: \.element) { index, objectId in
                                    if let object = store.objects.first(where: { $0.uuidValue == objectId }) {
                                        PanelContainer(
                                            object: object,
                                            index: index,
                                            isFocused: index == store.focusedPanelIndex,
                                            registry: registry,
                                            terminalRegistry: terminalRegistry,
                                            codeEditorRegistry: codeEditorRegistry,
                                            onFocus: { store.send(.focusPanel(index)) },
                                            onClose: { store.send(.closePanel(index)) },
                                            onMetadataUpdate: { updated in
                                                store.send(.updateObject(updated))
                                            },
                                            projectId: store.activeProjectId,
                                            projectName: store.projects.first(where: { $0.uuidValue == store.activeProjectId })?.name
                                        )
                                        .frame(width: panelWidth)
                                        .frame(maxHeight: .infinity)
                                        .id(objectId)
                                    }
                                }
                            }
                        }
                        .onChange(of: store.focusedPanelIndex) { _, newIndex in
                            guard newIndex < store.visiblePanelIds.count else { return }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(store.visiblePanelIds[newIndex], anchor: .center)
                            }
                        }
                        .onChange(of: store.visiblePanelIds.count) { oldCount, newCount in
                            // Scroll to new panel when one is added
                            if newCount > oldCount, store.focusedPanelIndex < store.visiblePanelIds.count {
                                let focusedId = store.visiblePanelIds[store.focusedPanelIndex]
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    proxy.scrollTo(focusedId, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: store.objects) { _, newObjects in
            let liveIds = Set(newObjects.map { $0.uuidValue })
            // Prune registry entries for deleted objects
            registry.sync(with: liveIds)
            terminalRegistry.sync(with: liveIds)
            codeEditorRegistry.sync(with: liveIds)
            // Prewarm link tabs if small set
            if newObjects.count <= warmUpThreshold {
                for object in newObjects where object.objectType == .link {
                    if let url = object.url {
                        _ = registry.ensureWebView(objectId: object.uuidValue, initialURL: url, onMetadata: handleMetadata)
                    }
                }
            }
        }
        .onDisappear {
            isActive = false
            registry.clearAll()
            terminalRegistry.clearAll()
            codeEditorRegistry.clearAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("KillAllWebViews"))) { _ in
            isActive = false
            registry.clearAll()
            terminalRegistry.clearAll()
            codeEditorRegistry.clearAll()
        }
    }

    private func handleMetadata(objectId: UUID, title: String?, currentURL: URL?, favicon: String?) {
        guard isActive else { return }
        guard let object = store.objects.first(where: { $0.uuidValue == objectId }) else { return }
        var updated = object
        if let t = title { updated.title = t }
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
        store.send(.updateObject(updated))
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

// MARK: - Panel Container

private struct PanelContainer: View {
    let object: TaskObject
    let index: Int
    let isFocused: Bool
    let registry: WebViewRegistry
    let terminalRegistry: TerminalRegistry
    let codeEditorRegistry: CodeEditorRegistry
    let onFocus: () -> Void
    let onClose: () -> Void
    let onMetadataUpdate: (TaskObject) -> Void
    var projectId: UUID? = nil
    var projectName: String? = nil

    @State private var isHeaderHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Panel header bar
            panelHeader

            Divider()

            // Content
            TabContentView(
                object: object,
                registry: registry,
                terminalRegistry: terminalRegistry,
                codeEditorRegistry: codeEditorRegistry,
                onMetadataUpdate: onMetadataUpdate,
                projectId: projectId,
                projectName: projectName
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            // Focus indicator at bottom
            if isFocused {
                Rectangle()
                    .fill(Color.slideAccent)
                    .frame(height: 2)
            }
        }
        .overlay(
            // Subtle border between panels
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.3))
                .frame(width: 1)
                .frame(maxHeight: .infinity),
            alignment: .trailing
        )
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
    }

    private var panelHeader: some View {
        HStack(spacing: 6) {
            // Object icon
            panelIcon
                .frame(width: 14, height: 14)

            // Title
            Text(object.title ?? "Untitled")
                .font(.system(size: 11, weight: isFocused ? .medium : .regular))
                .foregroundColor(isFocused ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Close button
            if isHeaderHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isFocused ? Color.slideAccent.opacity(0.06) : Color(NSColor.windowBackgroundColor))
        .onDrag { object.dragItemProvider() }
        .onHover { isHeaderHovered = $0 }
    }

    @ViewBuilder
    private var panelIcon: some View {
        switch object.kind {
        case .link:
            if let faviconURL = object.favicon, let url = URL(string: faviconURL) {
                KFImage(url)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .cornerRadius(2)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
            }
        case .pdf:
            Image(systemName: "doc.fill")
                .font(.system(size: 10))
                .foregroundColor(.red)
        case .note:
            Image(systemName: "note.text")
                .font(.system(size: 10))
                .foregroundColor(.orange)
        case .image:
            Image(systemName: "photo")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .video:
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.purple)
        case .audio:
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 10))
                .foregroundColor(.pink)
        case .terminal:
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .codeEditor:
            Image(systemName: "curlybraces")
                .font(.system(size: 10))
                .foregroundColor(.cyan)
        case .group:
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundColor(.cyan)
        }
    }
}

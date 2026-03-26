import ComposableArchitecture
import SlideDatabase
import SwiftUI
import Kingfisher
import UniformTypeIdentifiers

// MARK: - Content Sidebar View

struct ContentSidebarView: View {
    @Bindable var store: StoreOf<ContentBrowserFeature>
    @State private var draggingItem: UUID?
    @State private var showingFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Sort header
            sidebarHeader

            // Quick-add row (Arc-style)
            quickAddRow

            if store.filteredObjects.isEmpty {
                emptyState
            } else {
                objectList
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Sidebar Header

    private var sidebarHeader: some View {
        HStack {
            Text("\(store.filteredObjects.count) objects")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Menu {
                ForEach(SidebarSortMode.allCases, id: \.self) { mode in
                    Button {
                        store.send(.setSidebarSort(mode))
                    } label: {
                        HStack {
                            Text(mode.label)
                            if store.sidebarSort == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Quick Add Row

    private var quickAddRow: some View {
        HStack(spacing: 6) {
            quickAddButton(icon: "globe", tooltip: "New Web Tab") {
                store.send(.addLinkObject("New Tab", URL(string: "https://google.com")!))
            }
            quickAddButton(icon: "terminal", tooltip: "New Terminal") {
                store.send(.addTerminalObject("Terminal", "~"))
            }
            quickAddButton(icon: "note.text", tooltip: "New Note") {
                store.send(.addNoteObject("Untitled Note", ""))
            }
            quickAddButton(icon: "plus", tooltip: "Import File") {
                showingFilePicker = true
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .image, .movie, .audio, .plainText],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let fileType = FileManager.detectFileType(for: url)
                    let fileName = url.deletingPathExtension().lastPathComponent
                    switch fileType {
                    case .pdf: store.send(.addPDFObject(fileName, url))
                    case .image: store.send(.addImageObject(fileName, url))
                    case .video: store.send(.addVideoObject(fileName, url))
                    case .audio: store.send(.addAudioObject(fileName, url))
                    case .unknown:
                        if let content = try? String(contentsOf: url, encoding: .utf8) {
                            store.send(.addNoteObject(fileName, content))
                        }
                    }
                }
            }
        }
    }

    private func quickAddButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Object List

    private var objectList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.filteredObjects, id: \.uuid) { object in
                        let isInPanel = store.visiblePanelIds.contains(object.uuidValue)
                        let isFocused = store.selectedObjectId == object.uuidValue

                        SidebarObjectRow(
                            object: object,
                            isSelected: isInPanel,
                            isFocused: isFocused,
                            activityState: store.activityStates[object.uuidValue] ?? .idle,
                            badgeCount: store.badgeCounts[object.uuidValue] ?? 0,
                            onSelect: {
                                store.send(.selectObjectId(object.uuidValue))
                            },
                            onOpenInNewPanel: {
                                store.send(.openInNewPanel(object.uuidValue))
                            },
                            onDelete: {
                                store.send(.deleteObject(object.uuidValue))
                            },
                            onDuplicate: {
                                store.send(.duplicateObject(object.uuidValue))
                            },
                            onRename: { newTitle in
                                store.send(.renameObject(object.uuidValue, newTitle))
                            },
                            onResetName: {
                                store.send(.resetCustomName(object.uuidValue))
                            }
                        )
                        .onDrag { object.dragItemProvider() }
                        .id(object.uuid)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: store.selectedObjectId) { _, newId in
                if let id = newId,
                   let obj = store.objects.first(where: { $0.uuidValue == id }) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(obj.uuid, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No objects")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Press ⌘K to create one")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
    }
}

#Preview("Sidebar – Flat Library") {
    let store = Store(
        initialState: {
            let primary = TaskObject.createLink(title: "Arc Inspiration", url: URL(string: "https://arc.net")!)

            let child = TaskObject.createLink(title: "Sidebar References", url: URL(string: "https://example.com/sidebar")!)

            let note = TaskObject.createNote(title: "Interaction Notes", content: "Keyboard-first ideas")
            let pdf = TaskObject.createPDF(
                title: "Browser Systems",
                filePath: URL(fileURLWithPath: "/tmp/browser-systems.pdf"),
                originalFileName: "browser-systems.pdf"
            )

            var state = ContentBrowserFeature.State()
            state.objects = [primary, child, note, pdf]
            state.visiblePanelIds = [primary.uuidValue, note.uuidValue]
            state.focusedPanelIndex = 0
            return state
        }()
    ) {
        ContentBrowserFeature()
    }

    ContentSidebarView(store: store)
        .frame(width: 280, height: 520)
}

// MARK: - Sidebar Object Row

struct SidebarObjectRow: View {
    let object: TaskObject
    let isSelected: Bool
    var isFocused: Bool = false
    var activityState: ObjectActivityState = .idle
    var badgeCount: Int = 0
    let onSelect: () -> Void
    let onOpenInNewPanel: () -> Void
    let onDelete: () -> Void
    var onDuplicate: (() -> Void)? = nil
    var onRename: ((String) -> Void)? = nil
    var onResetName: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 8) {
            // Type icon
            objectIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Name", text: $renameText, onCommit: {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onRename?(trimmed)
                        }
                        isRenaming = false
                    })
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .onExitCommand { isRenaming = false }
                } else {
                    Text(object.displayTitle.isEmpty ? "Untitled" : object.displayTitle)
                        .font(.system(size: 12, weight: isFocused ? .semibold : (isSelected ? .medium : .regular)))
                        .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Activity dot
            if activityState != .idle {
                PulsingDot(color: activityState == .active ? .blue : .orange)
            }

            // Badge count
            if badgeCount > 0 && activityState == .idle {
                Text("\(badgeCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .overlay(alignment: .trailing) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
                .padding(.trailing, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused ? Color.accentColor.opacity(0.18) : (isSelected ? Color.accentColor.opacity(0.08) : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)))
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                onOpenInNewPanel()
            } else {
                onSelect()
            }
        }
        .contextMenu {
            if onRename != nil {
                Button("Rename") {
                    renameText = object.displayTitle.isEmpty ? (object.title ?? "") : object.displayTitle
                    isRenaming = true
                }
            }
            if !object.customName.isEmpty, onResetName != nil {
                Button("Reset Name") {
                    onResetName?()
                }
            }
            if onDuplicate != nil {
                Button("Duplicate") {
                    onDuplicate?()
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TriggerInlineRename"))) { notification in
            if let objectId = notification.userInfo?["objectId"] as? UUID,
               objectId == object.uuidValue,
               onRename != nil {
                renameText = object.displayTitle.isEmpty ? (object.title ?? "") : object.displayTitle
                isRenaming = true
            }
        }
    }

    // MARK: - Object Icon

    @ViewBuilder
    private var objectIcon: some View {
        switch object.kind {
        case .link:
            if let faviconURL = object.favicon, let url = URL(string: faviconURL) {
                KFImage(url)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .cornerRadius(3)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
            }
        case .pdf:
            Image(systemName: "doc.fill")
                .font(.system(size: 13))
                .foregroundColor(.red)
        case .note:
            Image(systemName: "note.text")
                .font(.system(size: 13))
                .foregroundColor(.orange)
        case .image:
            Image(systemName: "photo")
                .font(.system(size: 13))
                .foregroundColor(.green)
        case .video:
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 13))
                .foregroundColor(.purple)
        case .audio:
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 13))
                .foregroundColor(.pink)
        case .terminal:
            Image(systemName: "terminal")
                .font(.system(size: 13))
                .foregroundColor(.green)
        case .codeEditor:
            Image(systemName: "curlybraces")
                .font(.system(size: 13))
                .foregroundColor(.cyan)
        case .group:
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundColor(.cyan)
        }
    }
}

// MARK: - Pulsing Activity Dot

struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .fill(color.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing ? 2.0 : 1.0)
                    .opacity(isPulsing ? 0 : 1)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
    }
}
